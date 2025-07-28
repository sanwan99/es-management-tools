#!/bin/bash
echo "#######################################################################"
echo "es-reindex-shrink-optimized run time: $(date)"

# 7天前的数据进行重索引收缩
shrink_date=`date -d "7 days ago" "+%Y-%m-%d"`

echo "收缩日期: $shrink_date"

# 排除不需要收缩的索引模式
exclude_patterns=(
    "logstash-loghub-logs-iroom-prd-"
    "logstash-loghub-logs-platform-int-int-"
    "logstash-loghub-logs-guardian-prd-"
    "logstash-loghub-logs-website-platform-api-common-"
    "logstash-loghub-logs-product-room-api-prd-"
)

echo "排除的索引模式:"
for pattern in "${exclude_patterns[@]}"; do
    echo "  - $pattern*"
done
echo ""

# 获取该日期的所有索引（分片数>1）
all_indexes=$(curl -s "http://192.168.0.93:9201/_cat/indices?h=index,pri" | grep "$shrink_date" | awk '$2 > 1 {print $1}')

if [ -z "$all_indexes" ]; then
    echo "没有找到 $shrink_date 的多分片索引"
    exit 0
fi

# 应用排除规则
indexes=""
for index in $all_indexes; do
    should_exclude=false
    for pattern in "${exclude_patterns[@]}"; do
        if [[ "$index" == *"$pattern"* ]]; then
            should_exclude=true
            echo "跳过排除的索引: $index (匹配模式: $pattern*)"
            break
        fi
    done
    
    if [ "$should_exclude" = false ]; then
        indexes="$indexes $index"
    fi
done

if [ -z "$indexes" ]; then
    echo "没有需要收缩的索引"
    exit 0
fi

echo "开始处理索引..."
processed_count=0
success_count=0
failed_count=0

for index in $indexes; do
    echo "=== 处理索引: $index ==="
    processed_count=$((processed_count + 1))
    
    # 获取原索引信息
    original_docs=$(curl -s "http://192.168.0.93:9201/_cat/indices/${index}?h=docs.count")
    original_size=$(curl -s "http://192.168.0.93:9201/_cat/indices/${index}?h=store.size")
    original_shards=$(curl -s "http://192.168.0.93:9201/_cat/indices/${index}?h=pri")
    
    echo "原索引: $original_docs 文档, $original_size, $original_shards 分片"
    
    # 新索引名称
    new_index="${index}-shrunk"
    
    # 1. 检查新索引是否已存在
    check_result=$(curl -s "http://192.168.0.93:9201/_cat/indices/${new_index}" 2>/dev/null)
    if ! echo "$check_result" | grep -q "index_not_found_exception" && echo "$check_result" | grep -q "$new_index"; then
        echo "新索引 $new_index 已存在，跳过"
        continue
    fi
    
    # 2. 创建新索引（先不指定节点类型）
    echo "创建新索引: $new_index"
    create_result=$(curl -s -X PUT "http://192.168.0.93:9201/${new_index}" -H 'Content-Type: application/json' -d'
    {
      "settings": {
        "index.number_of_shards": 1,
        "index.number_of_replicas": 0,
        "index.codec": "best_compression"
      }
    }')
    
    if echo "$create_result" | grep -q '"acknowledged":true'; then
        echo "✅ 新索引创建成功"
    else
        echo "❌ 新索引创建失败: $create_result"
        failed_count=$((failed_count + 1))
        continue
    fi
    
    # 2.1 等待索引就绪
    echo "等待索引分片就绪..."
    curl -s "http://192.168.0.93:9201/_cluster/health/${new_index}?wait_for_status=yellow&timeout=60s" >/dev/null
    
    shard_state=$(curl -s "http://192.168.0.93:9201/_cat/shards/${new_index}?h=state" | tr -d ' ')
    if [ "$shard_state" != "STARTED" ]; then
        echo "❌ 分片未就绪: $shard_state"
        curl -s -X DELETE "http://192.168.0.93:9201/${new_index}" >/dev/null
        failed_count=$((failed_count + 1))
        continue
    fi
    echo "✅ 分片就绪"
    
    # 3. 执行重索引
    echo "开始重索引..."
    reindex_start_time=$(date +%s)
    reindex_result=$(curl -s -X POST "http://192.168.0.93:9201/_reindex" -H 'Content-Type: application/json' -d'
    {
      "source": {"index": "'$index'"},
      "dest": {"index": "'$new_index'"}
    }')
    
    if ! echo "$reindex_result" | grep -q '"failures":\[\]'; then
        echo "❌ 重索引启动失败: $reindex_result"
        curl -s -X DELETE "http://192.168.0.93:9201/${new_index}" >/dev/null
        failed_count=$((failed_count + 1))
        continue
    fi
    echo "✅ 重索引启动成功"
    
    # 4. 等待重索引完成（优化：降低监控频率）
    echo "等待重索引完成..."
    max_wait=3600  # 1小时超时
    wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        # 减少API调用频率：每180秒检查一次
        sleep 180
        wait_time=$((wait_time + 180))
        
        # 检查任务状态（简化检查，避免jq依赖）
        task_running=$(curl -s "http://192.168.0.93:9201/_tasks?actions=*reindex" 2>/dev/null | grep -c '"action":"indices:data/write/reindex"' || echo "0")
        
        if [ "$task_running" = "0" ]; then
            reindex_end_time=$(date +%s)
            reindex_duration=$((reindex_end_time - reindex_start_time))
            echo "✅ 重索引完成，耗时: ${reindex_duration}秒"
            break
        fi
        
        # 显示进度（每3分钟更新一次）
        current_docs=$(curl -s "http://192.168.0.93:9201/_cat/indices/${new_index}?h=docs.count" 2>/dev/null || echo "0")
        echo "   进度: $current_docs / $original_docs 文档 (${wait_time}s，3分钟检查间隔)"
    done
    
    if [ $wait_time -ge $max_wait ]; then
        echo "❌ 重索引超时"
        curl -s -X DELETE "http://192.168.0.93:9201/${new_index}" >/dev/null
        failed_count=$((failed_count + 1))
        continue
    fi
    
    # 5. 验证重索引结果
    echo "验证数据完整性..."
    echo "刷新新索引以确保数据可见..."
    curl -s -X POST "http://192.168.0.93:9201/${new_index}/_refresh" >/dev/null
    sleep 15  # 等待索引刷新
    
    new_docs=$(curl -s "http://192.168.0.93:9201/_cat/indices/${new_index}?h=docs.count")
    new_health=$(curl -s "http://192.168.0.93:9201/_cat/indices/${new_index}?h=health")
    
    if [ "$original_docs" != "$new_docs" ] || [ "$new_health" != "green" ]; then
        echo "❌ 验证失败: 文档数 $original_docs vs $new_docs, 健康: $new_health"
        curl -s -X DELETE "http://192.168.0.93:9201/${new_index}" >/dev/null
        failed_count=$((failed_count + 1))
        continue
    fi
    echo "✅ 数据验证成功"
    
    # 6. 段合并优化（新增关键步骤）
    echo "执行段合并优化..."
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
    
    # 7. 获取最终优化效果
    final_size=$(curl -s "http://192.168.0.93:9201/_cat/indices/${new_index}?h=store.size")
    segment_count=$(curl -s "http://192.168.0.93:9201/_cat/segments/${new_index}" | wc -l)
    
    echo "✅ 优化完成:"
    echo "   存储: $original_size → $final_size"
    echo "   分片: $original_shards → 1"
    echo "   段数: $segment_count"
    
    # 8. 迁移到Warm节点
    echo "迁移到Warm节点..."
    migrate_result=$(curl -s -X PUT "http://192.168.0.93:9201/${new_index}/_settings" -H 'Content-Type: application/json' -d'
    {
      "index.routing.allocation.require.node-type": "warm"
    }')
    
    if echo "$migrate_result" | grep -q '"acknowledged":true'; then
        echo "✅ 迁移命令成功"
        # 等待迁移完成（不阻塞太久）
        sleep 30
        final_node=$(curl -s "http://192.168.0.93:9201/_cat/shards/${new_index}?h=node" | tr -d ' ')
        echo "   当前节点: $final_node"
    else
        echo "⚠️ 迁移失败，但优化成功"
    fi
    
    # 9. 替换原索引
    echo "替换原索引..."
    curl -s -X DELETE "http://192.168.0.93:9201/${index}" >/dev/null
    
    curl -s -X POST "http://192.168.0.93:9201/_aliases" -H 'Content-Type: application/json' -d'
    {
      "actions": [
        {
          "add": {
            "index": "'$new_index'",
            "alias": "'$index'"
          }
        }
      ]
    }' >/dev/null
    
    echo "✅ 索引 $index 收缩完成"
    success_count=$((success_count + 1))
    echo "---"
done

echo ""
echo "=== 批量处理完成 ==="
echo "总计处理: $processed_count 个索引"
echo "成功收缩: $success_count 个索引"
echo "失败跳过: $failed_count 个索引"
echo ""
echo "es-reindex-shrink-optimized 任务完成: $(date)"