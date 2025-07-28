#!/bin/bash
echo "#######################################################################"
echo "es-close-data run time: $(date)"  

# 42天前的数据关闭（这些数据在7天时已经被收缩到1分片）
time1=`date -d "42 days ago" "+%Y-%m-%d"`

echo "关闭日期: $time1"

# 关闭索引（现在都是1分片，元数据压力大幅减少）
curl -XPOST http://192.168.0.95:9200/*${time1}*/_close -H "Content-Type: application/json" -d' {}'

echo "es-close-data 任务完成: $(date)"
