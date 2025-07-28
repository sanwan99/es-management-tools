#/bin/bash
echo "#######################################################################"
echo "cold-hot-data-migration run time: $(date)"  
time1=`date -d "3 days ago" "+%Y-%m-%d"`

curl -XPUT http://192.168.0.95:9200/*${time1}*/_settings?pretty -H "Content-Type: application/json" -d'
{
  "index.routing.allocation.require.node-type": "warm"
}'
