#!/bin/bash
echo "#######################################################################"
echo "测试重索引收缩脚本 - message-center索引"
echo "运行时间: $(date)"

# 7天前的数据进行重索引收缩
shrink_date=`date -d "6 days ago" "+%Y-%m-%d"`
test_pattern="logstash-loghub-logs-message-center"

echo "收缩日期: $shrink_date"
echo "测试索引模式: ${test_pattern}*"
echo ""

# 获取该日期的message-center索引（分片数>1）
echo "=== 查找测试索引 ==="
all_indexes=$(curl -s "http://192.168.0.93:9201/_cat/indices?h=index,pri" | grep "$shrink_date" | grep "$test_pattern" | awk '$2 > 1 {print $1}')

if [ -z "$all_indexes" ]; then
    echo "没有找到 $shrink_date 的 $test_pattern 多分片索引"
    echo ""
    echo "=== 显示该日期所有message-center索引 ==="
    curl -s "http://192.168.0.93:9201/_cat/indices?v&h=index,pri,docs.count,store.size" | grep "$shrink_date" | grep "$test_pattern"
    exit 0
fi

echo "找到以下测试索引:"
for index in $all_indexes; do
    shards=$(curl -s "http://192.168.0.93:9201/_cat/indices/${index}?h=pri")
    docs=$(curl -s "http://192.168.0.93:9201/_cat/indices/${index}?h=docs.count")
    size=$(curl -s "http://192.168.0.93:9201/_cat/indices/${index}?h=store.size")
    echo "  ✓ $index (分片: $shards, 文档: $docs, 大小: $size)"
done
echo ""

# 选择第一个索引进行测试
test_index=$(echo $all_indexes | awk '{print $1}')
echo "=== 选择测试索引: $test_index ==="

# 获取原索引详细信息
echo "=== 原索引详细信息 ==="
original_docs=$(curl -s "http://192.168.0.93:9201/_cat/indices/${test_index}?h=docs.count")
original_size=$(curl -s "http://192.168.0.93:9201/_cat/indices/${test_index}?h=store.size")
original_shards=$(curl -s "http://192.168.0.93:9201/_cat/indices/${test_index}?h=pri")
original_health=$(curl -s "http://192.168.0.93:9201/_cat/indices/${test_index}?h=health")

echo "索引名称: $test_index"
echo "文档数量: $original_docs"
echo "存储大小: $original_size"
echo "分片数量: $original_shards"
echo "健康状态: $original_health"
echo ""

echo "=== 分片分布情况 ==="
curl -s "http://192.168.0.93:9201/_cat/shards/${test_index}?v&h=shard,prirep,docs,store,node"
echo ""

# 新索引名称
new_index="${test_index}-test-shrunk"

# 检查新索引是否已存在
check_result=$(curl -s "http://192.168.0.93:9201/_cat/indices/${new_index}" 2>/dev/null)
if ! echo "$check_result" | grep -q "index_not_found_exception" && echo "$check_result" | grep -q "$new_index"; then
    echo "⚠️  测试索引 $new_index 已存在"
    echo "现有索引信息:"
    echo "$check_result"
    echo "是否删除现有测试索引？(y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        delete_result=$(curl -s -X DELETE "http://192.168.0.93:9201/${new_index}")
        if echo "$delete_result" | grep -q '"acknowledged":true'; then
            echo "✅ 已删除现有测试索引"
        else
            echo "❌ 删除失败: $delete_result"
            exit 1
        fi
    else
        echo "退出测试"
        exit 1
    fi
    echo ""
fi

echo "=== 开始重索引收缩测试 ==="

# 1. 创建新索引（先不指定节点类型，确保能成功创建）
echo "1. 创建测试索引: $new_index"
create_result=$(curl -s -X PUT "http://192.168.0.93:9201/${new_index}" -H 'Content-Type: application/json' -d'
{
  "settings": {
    "index.number_of_shards": 1,
    "index.number_of_replicas": 0,
    "index.codec": "best_compression"
  }
}')

echo "创建结果: $create_result"
if echo "$create_result" | grep -q '"acknowledged":true'; then
    echo "✅ 测试索引创建成功"
else
    echo "❌ 测试索引创建失败"
    exit 1
fi

# 1.1 等待索引就绪
echo "1.1 等待索引分片就绪..."
health_result=$(curl -s "http://192.168.0.93:9201/_cluster/health/${new_index}?wait_for_status=yellow&timeout=30s&pretty")
health_status=$(echo "$health_result" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
echo "健康检查结果: $health_status"

# 1.2 检查分片状态
echo "1.2 检查分片状态..."
curl -s "http://192.168.0.93:9201/_cat/shards/${new_index}?v&h=shard,prirep,state,node"

shard_state=$(curl -s "http://192.168.0.93:9201/_cat/shards/${new_index}?h=state" | tr -d ' ')
if [ "$shard_state" != "STARTED" ]; then
    echo "❌ 分片未就绪，状态: $shard_state"
    echo "尝试强制重新分配..."
    curl -s -X POST "http://192.168.0.93:9201/_cluster/reroute?retry_failed=true" >/dev/null
    sleep 10
    shard_state=$(curl -s "http://192.168.0.93:9201/_cat/shards/${new_index}?h=state" | tr -d ' ')
    if [ "$shard_state" != "STARTED" ]; then
        echo "❌ 分片仍未就绪: $shard_state"
        curl -s -X DELETE "http://192.168.0.93:9201/${new_index}"
        exit 1
    fi
fi
echo "✅ 分片状态正常: $shard_state"
echo ""

# 2. 执行重索引
echo "2. 开始重索引..."
reindex_start_time=$(date +%s)
reindex_result=$(curl -s -X POST "http://192.168.0.93:9201/_reindex" -H 'Content-Type: application/json' -d'
{
  "source": {
    "index": "'$test_index'"
  },
  "dest": {
    "index": "'$new_index'"
  }
}')

echo "重索引启动结果: $reindex_result"
if echo "$reindex_result" | grep -q '"failures":\[\]'; then
    # 检查是否同步完成（有"took"字段说明同步完成）
    if echo "$reindex_result" | grep -q '"took":'; then
        took_time=$(echo "$reindex_result" | grep -o '"took":[0-9]*' | cut -d':' -f2)
        took_seconds=$((took_time / 1000))
        echo "✅ 重索引同步完成，耗时: ${took_seconds}秒"
        reindex_completed=true
    else
        echo "✅ 重索引异步启动成功"
        reindex_completed=false
    fi
else
    echo "❌ 重索引启动失败"
    curl -s -X DELETE "http://192.168.0.93:9201/${new_index}"
    exit 1
fi
echo ""

# 3. 监控重索引进度（只有异步时才需要）
if [ "$reindex_completed" = false ]; then
    echo "3. 监控重索引进度..."
    max_wait=1800  # 30分钟超时
    wait_time=0

    while [ $wait_time -lt $max_wait ]; do
    # 优化：每180秒检查一次，减少对ES的干扰
    sleep 180
    wait_time=$((wait_time + 180))
    
    # 检查重索引是否完成：如果响应中有"took"字段，说明是同步完成
    if echo "$reindex_result" | grep -q '"took":'; then
        echo "✅ 重索引同步完成（检测到took字段）"
        break
    fi
    
    # 检查任务状态（移除jq依赖）
    task_running=$(curl -s "http://192.168.0.93:9201/_tasks?actions=*reindex" 2>/dev/null | grep -c '"action":"indices:data/write/reindex"' || echo "0")
    
    if [ "$task_running" = "0" ]; then
        reindex_end_time=$(date +%s)
        reindex_duration=$((reindex_end_time - reindex_start_time))
        echo "✅ 重索引异步完成，耗时: ${reindex_duration}秒"
        break
    fi
    
        # 显示当前新索引状态（每3分钟更新）
        current_docs=$(curl -s "http://192.168.0.93:9201/_cat/indices/${new_index}?h=docs.count" 2>/dev/null || echo "0")
        echo "   进度: $current_docs / $original_docs 文档 (${wait_time}s，3分钟检查间隔)"
    done
    
    if [ $wait_time -ge $max_wait ]; then
        echo "❌ 重索引超时"
        curl -s -X DELETE "http://192.168.0.93:9201/${new_index}"
        exit 1
    fi
else
    echo "3. 重索引已同步完成，跳过监控"
fi
echo ""

# 4. 验证结果
echo "4. 验证重索引结果..."
echo "刷新新索引以确保数据可见..."
curl -s -X POST "http://192.168.0.93:9201/${new_index}/_refresh" >/dev/null
sleep 10  # 等待索引刷新

new_docs=$(curl -s "http://192.168.0.93:9201/_cat/indices/${new_index}?h=docs.count")
new_size=$(curl -s "http://192.168.0.93:9201/_cat/indices/${new_index}?h=store.size")
new_health=$(curl -s "http://192.168.0.93:9201/_cat/indices/${new_index}?h=health")
new_shards=$(curl -s "http://192.168.0.93:9201/_cat/indices/${new_index}?h=pri")

echo "=== 结果对比 ==="
echo "原索引: $original_docs 文档, $original_size, $original_shards 分片, 健康: $original_health"
echo "新索引: $new_docs 文档, $new_size, $new_shards 分片, 健康: $new_health"
echo ""

echo "=== 新索引分片分布 ==="
curl -s "http://192.168.0.93:9201/_cat/shards/${new_index}?v&h=shard,prirep,docs,store,node"
echo ""

# 5. 段合并优化（新增关键步骤）
if [ "$original_docs" = "$new_docs" ] && [ "$new_health" = "green" ] && [ "$new_shards" = "1" ]; then
    echo "5. 执行段合并优化..."
    forcemerge_start_time=$(date +%s)
    curl -s -X POST "http://192.168.0.93:9201/${new_index}/_forcemerge?max_num_segments=1" >/dev/null
    
    # 等待段合并完成
    echo "等待段合并完成..."
    max_merge_wait=1800  # 30分钟超时
    merge_wait_time=0
    
    while [ $merge_wait_time -lt $max_merge_wait ]; do
        sleep 30
        merge_wait_time=$((merge_wait_time + 30))
        
        # 检查段合并任务
        merge_running=$(curl -s "http://192.168.0.93:9201/_tasks?actions=*forcemerge" 2>/dev/null | grep -c '"action":"indices:admin/forcemerge"' || echo "0")
        
        if [ "$merge_running" = "0" ]; then
            forcemerge_end_time=$(date +%s)
            forcemerge_duration=$((forcemerge_end_time - forcemerge_start_time))
            echo "✅ 段合并完成，耗时: ${forcemerge_duration}秒"
            break
        fi
        
        echo "   段合并中... (${merge_wait_time}s)"
    done
    
    if [ $merge_wait_time -ge $max_merge_wait ]; then
        echo "⚠️ 段合并超时，但重索引成功"
    fi
    
    # 获取段合并后的存储大小
    merge_after_size=$(curl -s "http://192.168.0.93:9201/_cat/indices/${new_index}?h=store.size")
    segment_count=$(curl -s "http://192.168.0.93:9201/_cat/segments/${new_index}" | wc -l)
    echo "段合并后存储: $merge_after_size (段数: $segment_count)"
    
    # 6. 尝试将索引迁移到Warm节点
    echo "6. 尝试迁移到Warm节点..."
    migrate_result=$(curl -s -X PUT "http://192.168.0.93:9201/${new_index}/_settings" -H 'Content-Type: application/json' -d'
    {
      "index.routing.allocation.require.node-type": "warm"
    }')
    
    if echo "$migrate_result" | grep -q '"acknowledged":true'; then
        echo "✅ 迁移命令发送成功，等待迁移完成..."
        sleep 30
        final_node=$(curl -s "http://192.168.0.93:9201/_cat/shards/${new_index}?h=node" | tr -d ' ')
        echo "   最终节点: $final_node"
        
        # 检查是否在Warm节点
        if curl -s "http://192.168.0.93:9201/_cat/nodes?h=name,node.role" | grep "$final_node" | grep -q "dil"; then
            echo "✅ 成功迁移到Warm节点"
        else
            echo "⚠️  节点类型验证: $final_node (可能不是Warm节点，但迁移命令已执行)"
        fi
    else
        echo "⚠️  迁移到Warm节点失败，但数据收缩成功"
    fi
    echo ""
fi

# 验证数据完整性
if [ "$original_docs" = "$new_docs" ] && [ "$new_health" = "green" ] && [ "$new_shards" = "1" ]; then
    echo "✅ 验证成功！"
    echo "   - 文档数量匹配: $new_docs"
    echo "   - 健康状态正常: $new_health" 
    echo "   - 分片数收缩: $original_shards -> $new_shards"
    
    # 计算压缩效果
    if [[ "$original_size" =~ ^[0-9.]+([kmgt]?)b$ ]] && [[ "$new_size" =~ ^[0-9.]+([kmgt]?)b$ ]]; then
        echo "   - 存储优化: $original_size -> $new_size"
    fi
    
    echo ""
    echo "🎉 测试完全成功！"
    echo ""
    echo "7. 测试完整替换流程..."
    echo "是否测试删除原索引并创建别名？这将完全模拟生产流程 (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "删除原索引: $test_index"
        curl -s -X DELETE "http://192.168.0.93:9201/${test_index}" >/dev/null
        
        echo "创建别名: $test_index -> $new_index"
        curl -s -X POST "http://192.168.0.93:9201/_aliases" -H 'Content-Type: application/json' -d'
        {
          "actions": [
            {
              "add": {
                "index": "'$new_index'",
                "alias": "'$test_index'"
              }
            }
          ]
        }' >/dev/null
        
        echo "✅ 完整替换流程完成"
        echo ""
        echo "验证替换结果:"
        curl -s "http://192.168.0.93:9201/_cat/indices/${test_index}?v&h=index,docs.count,store.size,pri"
        echo ""
        echo "现在通过原索引名查询的实际是优化后的索引！"
        
        # 询问是否恢复
        echo ""
        echo "是否恢复原索引（撤销替换）？(y/N)"
        read -r restore_response
        if [[ "$restore_response" =~ ^[Yy]$ ]]; then
            echo "恢复过程需要手动处理，因为原索引数据已删除"
            echo "当前别名指向: $new_index"
        fi
        
    else
        echo "跳过替换测试"
        echo ""
        echo "是否删除测试索引 $new_index？(y/N)"
        read -r delete_response
        if [[ "$delete_response" =~ ^[Yy]$ ]]; then
            curl -s -X DELETE "http://192.168.0.93:9201/${new_index}"
            echo "测试索引已删除"
        else
            echo "保留测试索引: $new_index"
        fi
    fi
    
else
    echo "❌ 验证失败！"
    echo "   - 文档匹配: $original_docs vs $new_docs $([ "$original_docs" = "$new_docs" ] && echo "✅" || echo "❌")"
    echo "   - 健康状态: $new_health $([ "$new_health" = "green" ] && echo "✅" || echo "❌")"
    echo "   - 分片收缩: $original_shards -> $new_shards $([ "$new_shards" = "1" ] && echo "✅" || echo "❌")"
    echo ""
    echo "保留测试索引以便调试: $new_index"
fi

echo ""
echo "测试完成: $(date)"