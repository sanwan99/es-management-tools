# ES集群节点被踢出故障根因分析报告

## 故障现象
- 节点被踢出集群，显示`failed [3] consecutive checks`
- 集群状态不稳定，节点频繁离线
- 集群健康状态异常，分片无法正常分配

## 受影响节点详情

### 节点1：node-cardano-2 (主节点)
- **节点名称**: `node-cardano-2`
- **节点ID**: `LIvZ5aZARcy1WriioM1rUg`
- **IP地址**: `192.168.0.94:9301`
- **节点类型**: `cardano` (主节点)
- **踢出时间**: `2025-07-17T01:30:51`
- **踢出原因**: 连续3次健康检查失败
- **当前状态**: 可能已重新加入集群

### 节点2：node-warm-1 (数据节点)
- **节点名称**: `node-warm-1`
- **节点ID**: `uyS2zxILQqqpJ5VGQnUaXA`
- **IP地址**: `192.168.0.90:9301`
- **节点类型**: `warm` (数据节点)
- **踢出时间**: `2025-07-18T04:07:10`
- **踢出原因**: 集群状态应用超时(6.5分钟)
- **当前状态**: 尝试重新加入集群但找不到主节点

### 故障时间线
```
2025-07-17T01:30:51 → node-cardano-2 开始出现健康检查失败
2025-07-17T01:32:48 → node-cardano-2 继续故障检测失败
2025-07-17T01:35:14 → node-cardano-2 继续故障检测失败  
2025-07-17T01:37:45 → node-cardano-2 继续故障检测失败
2025-07-18T04:07:10 → node-warm-1 被从集群中移除
2025-07-18T04:13:34 → node-warm-1 尝试重新加入但找不到主节点
```

## 初步分析误区
**错误判断**: 认为是网络抖动导致的故障检测超时  
**实际原因**: 分片数量过多 + 磁盘性能差导致的集群状态同步瓶颈

## 关键日志分析

### 1. node-cardano-2 故障检测失败日志
```log
[2025-07-17T01:30:51,059][INFO ][o.e.c.c.Coordinator] [node-warm-1] 
master node [{node-cardano-2}{LIvZ5aZARcy1WriioM1rUg}{lYo6NoRuT1mBVeUlZTzSWQ}{192.168.0.94}{192.168.0.94:9301}] failed, restarting discovery
org.elasticsearch.ElasticsearchException: node [{node-cardano-2}] failed [3] consecutive checks
```
**问题**: node-cardano-2 连续3次健康检查失败，触发故障检测机制

### 2. node-warm-1 集群状态应用超时日志
```log
[2025-07-18T04:14:47,405][WARN ][o.e.c.s.ClusterApplierService] [node-warm-1] 
cluster state applier task took [6.5m] which is above the warn threshold of [30s]: 
[running applier [org.elasticsearch.indices.cluster.IndicesClusterStateService@13dad2d4]] took [392655ms]
```
**问题**: node-warm-1 集群状态应用耗时6.5分钟，索引状态服务处理耗时392秒

### 3. node-warm-1 被移除日志
```log
[2025-07-18T04:07:10,977][INFO ][o.e.c.s.ClusterApplierService] [node-warm-3] 
master node changed {current [{node-cardano-3}]}, 
removed {{node-warm-1}}, term: 73042
```
**问题**: node-warm-1 被从集群中移除，node-cardano-3 成为新的主节点

### 4. 索引状态服务性能瓶颈
```log
[2025-07-18T06:04:23,550][WARN ][o.e.c.s.ClusterApplierService] [node-warm-3] 
cluster state applier task took [1.2m] which is above the warn threshold of [30s]: 
[running applier [org.elasticsearch.indices.cluster.IndicesClusterStateService@4f189c48]] took [64877ms]
```
**问题**: 索引状态服务处理耗时64秒，远超30秒警告阈值

### 5. 悬挂索引处理异常
```log
[notifying listener [org.elasticsearch.gateway.DanglingIndicesState@5fb3532c]] took [51920ms]
```
**问题**: 悬挂索引状态处理耗时51秒

## 性能瓶颈时间分析

### 节点故障对比
| 节点 | 故障类型 | 处理时间 | 超时倍数 | 影响 |
|------|----------|----------|----------|------|
| node-cardano-2 | 健康检查失败 | 3次×10s=30s | 3倍 | 主节点离线 |
| node-warm-1 | 集群状态应用超时 | 6.5分钟 | 13倍 | 数据节点离线 |

### 组件性能瓶颈
| 组件 | 正常耗时 | 异常耗时 | 超时倍数 |
|------|----------|----------|----------|
| IndicesClusterStateService | <1s | 64.8s | 64倍 |
| DanglingIndicesState | <1s | 51.9s | 51倍 |
| 集群状态应用总时间 | <30s | 390s | 13倍 |

## 悬挂索引（Dangling Indices）详解

### 什么是悬挂索引
**悬挂索引**是指存在于磁盘上但不在集群元数据中的索引。通俗来说，就是"孤儿索引"。

### 悬挂索引产生原因

1. **节点异常离线**
   - 节点突然断电、宕机
   - 网络分区导致节点脱离集群
   - 进程异常终止

2. **索引删除不完整**
   - 删除索引时部分节点离线
   - 集群状态同步失败
   - 分片删除操作未完成

3. **集群重建**
   - 集群完全重启后元数据丢失
   - 主节点选举失败
   - 元数据恢复不完整

### 悬挂索引的影响

1. **性能影响**
   - 集群启动时需要扫描和处理
   - 占用磁盘空间和内存资源
   - 拖慢集群状态同步

2. **稳定性影响**
   - 可能导致集群状态不一致
   - 影响分片分配决策
   - 造成节点响应超时

### 悬挂索引处理流程

```
节点启动 → 扫描本地磁盘 → 发现悬挂索引 → 与集群元数据对比 → 
决定导入/删除 → 更新集群状态 → 完成处理
```

## 根本原因分析：分片数量过多 + 磁盘性能差

### 1. 性能公式
```
处理时间 = 分片数量 × 单个分片处理时间 × 磁盘IO延迟倍数
```

**示例计算**：
- 正常环境：1000分片 × 0.1ms × 1 = 100ms
- 当前环境：10000分片 × 0.1ms × 64 = 64000ms (64秒)

### 2. 分片数量影响
- 每个分片都需要维护状态信息
- 集群状态同步时需要处理所有分片的元数据
- 分片越多，`IndicesClusterStateService` 处理时间越长
- 大量分片导致内存压力和GC频繁

### 3. 磁盘性能影响
- 悬挂索引扫描需要遍历磁盘目录
- 索引状态同步需要读写磁盘元数据
- 磁盘IO成为瓶颈时，处理时间呈指数级增长
- 机械硬盘的随机读写性能严重影响集群状态同步

### 4. 故障链路分析

#### node-cardano-2 故障链路
```
网络抖动/连接问题 → 健康检查超时 → 连续3次检查失败 → 触发故障检测 → 节点被踢出集群
```

#### node-warm-1 故障链路
```
大量分片 + 磁盘性能差 → 索引状态服务处理缓慢 → 悬挂索引处理阻塞 → 
集群状态应用超时(6.5分钟) → 节点响应超过故障检测阈值 → 节点被踢出集群
```

#### 集群整体影响
```
主节点离线 → 主节点重新选举 → 集群状态重建 → 数据节点状态同步压力增加 → 
更多节点响应超时 → 集群稳定性下降 → 服务可用性受影响
```

## 诊断验证方法

### 1. 检查分片数量
```bash
# 检查分片总数
curl -s "http://192.168.0.93:9201/_cat/shards?h=index,shard,prirep,state" | wc -l

# 检查每个节点的分片数
curl -s "http://192.168.0.93:9201/_cat/shards?h=node,index,shard" | sort | uniq -c

# 检查集群分片统计
curl -s "http://192.168.0.93:9201/_cluster/stats?pretty" | grep -A10 "shards"
```

### 2. 检查磁盘性能
```bash
# 检查磁盘IO性能
iostat -x 1 5
# 重点看 %util 和 await 指标

# 检查磁盘使用情况
df -h

# 检查磁盘类型
lsblk -d -o name,rota
# rota=1 表示机械硬盘，rota=0 表示SSD
```

### 3. 检查悬挂索引
```bash
# 查看悬挂索引
curl -s "http://192.168.0.93:9201/_dangling"

# 查看集群状态中的悬挂索引信息
curl -s "http://192.168.0.93:9201/_cluster/state/metadata?pretty" | grep -i dangling
```

### 4. 验证节点状态
```bash
# 检查当前在线节点
curl -s "http://192.168.0.93:9201/_cat/nodes?v"

# 检查node-cardano-2是否重新加入
curl -s "http://192.168.0.93:9201/_cat/nodes?v" | grep "192.168.0.94"

# 检查node-warm-1是否重新加入
curl -s "http://192.168.0.93:9201/_cat/nodes?v" | grep "192.168.0.90"

# 直接访问被踢出的节点
curl -s "http://192.168.0.94:9201/_cluster/health"
curl -s "http://192.168.0.90:9201/_cluster/health"
```

## 解决方案

### 1. 优先级1：减少分片数量（治本）

#### 索引模板优化
```bash
# 设置合理的分片数
PUT _template/shard_template
{
  "index_patterns": ["*"],
  "settings": {
    "number_of_shards": 1,        # 小索引使用1个分片
    "number_of_replicas": 1,      # 根据需要设置副本数
    "refresh_interval": "30s"     # 减少刷新频率
  }
}
```

#### 索引合并
```bash
# 合并小索引
POST _reindex
{
  "source": {"index": "small_index_*"},
  "dest": {"index": "merged_index"}
}

# 删除原始小索引
DELETE small_index_*
```

#### 分片数量限制
```yaml
# elasticsearch.yml
cluster.max_shards_per_node: 10000  # 限制单节点分片数
```

### 2. 优先级2：提升磁盘性能（治本）

#### 硬件升级
```bash
# 使用SSD替代HDD
# 增加磁盘并发处理能力
# 使用RAID 0或RAID 10提升性能
```

#### 磁盘优化
```bash
# 优化磁盘挂载参数
mount -o noatime,data=writeback /dev/sdb /data/es

# 调整磁盘调度算法
echo noop > /sys/block/sdb/queue/scheduler
```

#### IO性能优化
```yaml
# elasticsearch.yml
# 优化数据路径分布
path.data: 
  - /data1/es/data
  - /data2/es/data
  - /data3/es/data

# 优化索引恢复参数
indices.recovery.max_bytes_per_sec: 200mb
indices.recovery.concurrent_streams: 8
```

### 3. 优先级3：集群配置优化（治标）

#### 集群状态同步优化
```yaml
# elasticsearch.yml
# 集群状态应用优化
cluster.service.slow_task_logging_threshold: 120s
cluster.routing.allocation.disk.watermark.low: 85%
cluster.routing.allocation.disk.watermark.high: 90%

# 网关恢复优化
gateway.recover_after_time: 5m
gateway.expected_nodes: 6
gateway.auto_import_dangling_indices: false  # 禁止自动导入悬挂索引
```

#### 故障检测参数调优
```yaml
# elasticsearch.yml
# 增加故障检测容忍度（需要重启）
cluster.fault_detection.leader_check.timeout: 30s
cluster.fault_detection.leader_check.retry_count: 5
cluster.fault_detection.follower_check.timeout: 30s
cluster.fault_detection.follower_check.retry_count: 5
```

### 4. 悬挂索引处理

#### 清理悬挂索引
```bash
# 查看悬挂索引
curl -s "http://192.168.0.93:9201/_dangling"

# 删除悬挂索引（谨慎操作）
curl -X DELETE "http://192.168.0.93:9201/_dangling/{index_uuid}?accept_data_loss=true"

# 或者导入悬挂索引
curl -X POST "http://192.168.0.93:9201/_dangling/{index_uuid}?accept_data_loss=true"
```

## 监控告警体系

### 1. 关键监控指标

**分片相关**：
```bash
# 分片总数
total_shards < 20000

# 单节点分片数
shards_per_node < 1000

# 未分配分片数
unassigned_shards = 0
```

**磁盘性能**：
```bash
# 磁盘IO等待时间
disk_await < 10ms

# 磁盘使用率
disk_util < 80%

# 磁盘空间使用率
disk_usage < 85%
```

**集群状态**：
```bash
# 集群状态应用时间
cluster_state_apply_time < 30s

# 悬挂索引数量
dangling_indices_count = 0

# 节点离线数量
offline_nodes_count = 0
```

### 2. 告警规则
```yaml
# 分片数量告警
- alert: TooManyShards
  expr: elasticsearch_cluster_shards_total > 20000
  annotations:
    summary: "ES集群分片数量过多"

# 磁盘性能告警
- alert: HighDiskAwait
  expr: node_disk_await > 50
  annotations:
    summary: "磁盘IO等待时间过长"

# 集群状态告警
- alert: SlowClusterStateApply
  expr: elasticsearch_cluster_state_apply_time > 60
  annotations:
    summary: "集群状态应用时间过长"
```

## 预防措施

### 1. 索引生命周期管理
```bash
# 设置ILM策略
PUT _ilm/policy/log_policy
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_size": "10gb",
            "max_age": "1d"
          }
        }
      },
      "warm": {
        "min_age": "2d",
        "actions": {
          "forcemerge": {
            "max_num_segments": 1
          }
        }
      },
      "delete": {
        "min_age": "30d"
      }
    }
  }
}
```

### 2. 容量规划
```bash
# 分片数量规划
每个分片大小：10-50GB
每个节点分片数：< 1000
总分片数：< 节点数 × 1000

# 磁盘性能规划
推荐使用SSD
磁盘IO等待时间：< 10ms
磁盘使用率：< 85%
```

### 3. 运维规范
- 定期清理不必要的索引
- 优雅关闭节点避免产生悬挂索引
- 监控集群健康状态和性能指标
- 建立索引生命周期管理策略

## 性能基准对比

| 场景 | 分片数 | 磁盘类型 | 集群状态应用时间 | 故障风险 |
|------|--------|----------|------------------|----------|
| 理想环境 | <5000 | SSD | <5s | 低 |
| 可接受环境 | 5000-10000 | SSD | 5-15s | 中 |
| 警告环境 | 10000-20000 | HDD | 15-30s | 高 |
| 危险环境 | >20000 | HDD | >30s | 极高 |

## 总结

**根本原因**: 分片数量过多 + 磁盘性能差 = 集群状态同步瓶颈

**核心问题**: 
- 分片数量过多导致元数据处理压力大
- 磁盘性能差导致IO成为瓶颈
- 集群状态同步耗时超过故障检测阈值

**解决策略**: 
1. **治本**: 减少分片数量 + 提升磁盘性能
2. **治标**: 调整故障检测和集群状态同步参数
3. **预防**: 建立监控告警和运维规范

**关键指标**: 
- 分片数量/节点 < 1000
- 磁盘IO等待时间 < 10ms
- 集群状态应用时间 < 30s

**经验教训**: 
- 不要盲目调整超时参数，要找到性能瓶颈的根本原因
- 分片数量和磁盘性能是ES集群性能的关键因素
- 集群状态同步是ES稳定性的核心，必须重点监控