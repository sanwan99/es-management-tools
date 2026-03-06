#!/bin/bash

# ES索引漏网之鱼关闭脚本
# 用于关闭那些应该被关闭但仍然开启的旧索引
# 手动执行，不定时运行

echo "========================================================================="
echo "ES索引漏网之鱼关闭脚本"
echo "执行时间: $(date)"
echo "========================================================================="

# ES地址配置
ES_HOST="http://192.168.0.93:9201"

# 批量操作配置
BATCH_SIZE=50  # 单次批量关闭的最大索引数量，避免ES压力过大

# 批量关闭索引函数
batch_close_indices() {
    local indices_file="$1"
    local total_count=$(wc -l < "$indices_file")
    
    if [[ $total_count -le $BATCH_SIZE ]]; then
        # 如果索引数量不超过批量大小，直接批量关闭
        echo "🚀 索引数量($total_count)不超过批量限制($BATCH_SIZE)，执行单次批量关闭..."
        
        index_list=$(awk '{print $1}' "$indices_file" | tr '\n' ',' | sed 's/,$//')
        response=$(curl -s --connect-timeout 30 --max-time 60 -XPOST "$ES_HOST/$index_list/_close" -H "Content-Type: application/json" -d'{}')
        
        if echo "$response" | grep -q '"acknowledged":true'; then
            echo "✅ 批量关闭成功！所有 $total_count 个索引已关闭"
            return 0
        else
            echo "❌ 批量关闭失败: ${response:0:200}..."
            return 1
        fi
    else
        # 如果索引数量过多，分批关闭
        echo "🔄 索引数量($total_count)超过批量限制($BATCH_SIZE)，分批执行..."
        
        local batch_num=1
        local success_batches=0
        local failed_batches=0
        
        # 分批处理
        while IFS= read -r -d '' batch_file; do
            echo "📦 处理第 $batch_num 批 (最多 $BATCH_SIZE 个索引)..."
            
            index_list=$(awk '{print $1}' "$batch_file" | tr '\n' ',' | sed 's/,$//')
            batch_count=$(wc -l < "$batch_file")
            
            response=$(curl -s --connect-timeout 30 --max-time 60 -XPOST "$ES_HOST/$index_list/_close" -H "Content-Type: application/json" -d'{}')
            
            if echo "$response" | grep -q '"acknowledged":true'; then
                echo "✅ 第 $batch_num 批成功关闭 $batch_count 个索引"
                ((success_batches++))
            else
                echo "❌ 第 $batch_num 批失败: ${response:0:100}..."
                ((failed_batches++))
            fi
            
            ((batch_num++))
            rm -f "$batch_file"
            
            # 批次之间稍作延迟，避免给ES造成压力
            sleep 1
        done < <(split -l "$BATCH_SIZE" "$indices_file" /tmp/es_batch_ 2>/dev/null && find /tmp -name "es_batch_*" -print0)
        
        echo "📊 分批关闭结果: 成功 $success_batches 批, 失败 $failed_batches 批"
        return $failed_batches
    fi
}

# 检查ES连接
echo "🔍 检查ES连接..."
echo "   测试地址: $ES_HOST/_cluster/health"

# 先测试连接并显示结果
response=$(curl -s --connect-timeout 15 --max-time 30 "$ES_HOST/_cluster/health" 2>&1)
exit_code=$?

echo "   响应代码: $exit_code"
echo "   响应内容: ${response:0:100}..."

# 检查响应是否包含集群信息（即使curl返回非0，只要有正确响应就认为连接成功）
if echo "$response" | grep -q "cluster_name"; then
    echo "✅ ES连接正常（有效的集群响应）"
elif [ $exit_code -ne 0 ]; then
    echo "❌ 无法连接到ES集群: $ES_HOST"
    echo "   错误: $response"
    exit 1
else
    echo "❌ ES集群响应异常: $ES_HOST"
    echo "   响应: $response"
    exit 1
fi

# 计算关闭日期阈值 (42天前)
threshold_date=$(date -d "42 days ago" "+%Y-%m-%d")
echo "📅 关闭阈值日期: $threshold_date (42天前)"

# 获取所有开启的索引
echo ""
echo "🔍 扫描所有开启的索引..."
temp_file="/tmp/es_open_indices.txt"
curl -s --connect-timeout 10 --max-time 30 "$ES_HOST/_cat/indices?h=index,status&format=json" | \
    jq -r '.[] | select(.status == "open") | .index' | \
    grep -E '[0-9]{4}-[0-9]{2}-[0-9]{2}' | \
    sort > "$temp_file"

total_open=$(wc -l < "$temp_file")
echo "📊 发现 $total_open 个开启的索引"

# 筛选应该关闭的索引
echo ""
echo "🎯 分析应该关闭的索引..."
should_close_file="/tmp/es_should_close.txt"
> "$should_close_file"

while read -r index_name; do
    # 提取索引中的日期
    if [[ $index_name =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
        index_date="${BASH_REMATCH[1]}"
        
        # 比较日期，如果索引日期早于阈值日期，则应该关闭
        if [[ "$index_date" < "$threshold_date" ]]; then
            echo "$index_name ($index_date)" >> "$should_close_file"
        fi
    fi
done < "$temp_file"

# 统计结果
should_close_count=$(wc -l < "$should_close_file")
echo "📋 发现 $should_close_count 个应该关闭的索引"

if [[ $should_close_count -eq 0 ]]; then
    echo "✅ 没有发现需要关闭的漏网之鱼索引"
    rm -f "$temp_file" "$should_close_file"
    exit 0
fi

# 显示详细列表
echo ""
echo "📄 应该关闭的索引列表:"
echo "--------------------------------------------------------------------"
cat -n "$should_close_file"
echo "--------------------------------------------------------------------"

# 按日期分组统计
echo ""
echo "📊 按日期分组统计:"
awk '{print $2}' "$should_close_file" | sed 's/[()]//g' | sort | uniq -c | \
    awk '{printf "  %s: %d个索引\n", $2, $1}'

# 用户确认
echo ""
echo "⚠️  注意: 关闭索引不会删除数据，可以随时重新打开"
echo "⚠️  确认要关闭这 $should_close_count 个索引吗?"
echo ""
echo "选择操作:"
echo "  1) 全部关闭"
echo "  2) 选择性关闭"  
echo "  3) 仅显示命令，不执行"
echo "  0) 取消退出"
echo ""
read -p "请选择 [0-3]: " choice

case $choice in
    1)
        echo ""
        echo "🔧 开始智能批量关闭所有索引..."
        echo "📋 准备关闭 $should_close_count 个索引 (批量大小限制: $BATCH_SIZE)..."
        
        # 使用批量关闭函数
        if ! batch_close_indices "$should_close_file"; then
            echo ""
            echo "⚠️  批量关闭部分失败，尝试逐个关闭失败的索引..."
            
            # 回退到逐个关闭
            success_count=0
            failed_count=0
            
            while read -r line; do
                index_name=$(echo "$line" | awk '{print $1}')
                echo -n "  关闭 $index_name ... "
                
                if curl -s --connect-timeout 10 --max-time 15 -XPOST "$ES_HOST/$index_name/_close" -H "Content-Type: application/json" -d'{}' | grep -q '"acknowledged":true'; then
                    echo "✅"
                    ((success_count++))
                else
                    echo "❌"
                    ((failed_count++))
                fi
            done < "$should_close_file"
            
            echo ""
            echo "📊 逐个关闭结果: 成功 $success_count 个, 失败 $failed_count 个"
        fi
        ;;
        
    2)
        echo ""
        echo "📝 选择性关闭模式 (输入行号，多个用空格分隔，如: 1 3 5-8)"
        read -p "请输入要关闭的索引行号: " line_numbers
        
        # 解析行号范围
        selected_indices="/tmp/es_selected.txt"
        > "$selected_indices"
        
        for range in $line_numbers; do
            if [[ $range =~ ^([0-9]+)-([0-9]+)$ ]]; then
                # 范围格式 (如: 5-8)
                start=${BASH_REMATCH[1]}
                end=${BASH_REMATCH[2]}
                for ((i=start; i<=end; i++)); do
                    sed -n "${i}p" "$should_close_file" >> "$selected_indices"
                done
            elif [[ $range =~ ^[0-9]+$ ]]; then
                # 单个行号
                sed -n "${range}p" "$should_close_file" >> "$selected_indices"
            fi
        done
        
        selected_count=$(wc -l < "$selected_indices")
        echo ""
        echo "📋 已选择 $selected_count 个索引:"
        cat -n "$selected_indices"
        echo ""
        read -p "确认关闭这些索引? (y/N): " confirm
        
        if [[ $confirm =~ ^[Yy]$ ]]; then
            echo ""
            echo "🔧 开始智能批量关闭选中的索引..."
            echo "📋 准备关闭 $selected_count 个索引 (批量大小限制: $BATCH_SIZE)..."
            
            # 使用批量关闭函数
            if ! batch_close_indices "$selected_indices"; then
                echo ""
                echo "⚠️  批量关闭部分失败，尝试逐个关闭失败的索引..."
                
                # 回退到逐个关闭
                while read -r line; do
                    index_name=$(echo "$line" | awk '{print $1}')
                    echo -n "  关闭 $index_name ... "
                    
                    if curl -s --connect-timeout 10 --max-time 15 -XPOST "$ES_HOST/$index_name/_close" -H "Content-Type: application/json" -d'{}' | grep -q '"acknowledged":true'; then
                        echo "✅"
                    else
                        echo "❌"
                    fi
                done < "$selected_indices"
            fi
        else
            echo "❌ 操作已取消"
        fi
        rm -f "$selected_indices"
        ;;
        
    3)
        echo ""
        echo "📋 关闭命令预览 (仅显示，不执行):"
        echo "--------------------------------------------------------------------"
        while read -r line; do
            index_name=$(echo "$line" | awk '{print $1}')
            echo "curl -XPOST \"$ES_HOST/$index_name/_close\" -H \"Content-Type: application/json\" -d'{}'"
        done < "$should_close_file"
        echo "--------------------------------------------------------------------"
        ;;
        
    0)
        echo "❌ 操作已取消"
        ;;
        
    *)
        echo "❌ 无效选择"
        ;;
esac

# 清理临时文件
rm -f "$temp_file" "$should_close_file"

echo ""
echo "========================================================================="
echo "脚本执行完成: $(date)"
echo "========================================================================="