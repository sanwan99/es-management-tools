# two weeks
delete_time=`date -d "180 days ago" "+%Y-%m-%d"`

curl -XDELETE http://192.168.0.93:9200/*${delete_time}*

echo "es-delete-data run ok!"
