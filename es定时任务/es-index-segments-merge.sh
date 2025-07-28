#/bin/bash
# 按索引创建策略来调整段合并策略
#   因为现在都是按天新建索引的，所以对两天前的索引进行段合并
echo "#######################################################################"
echo "es-index-segments-merge run start time: $(date)"
segments_merge_time=`date -d "7 days ago" "+%Y-%m-%d"`
echo -e "\n segments-merge: logstash-loghub-*-$segments_merge_time"
curl -XPOST http://192.168.0.94:9200/*${segments_merge_time}*/_forcemerge?max_num_segments=1
echo "es-index-segments-merge run end time: $(date)"
