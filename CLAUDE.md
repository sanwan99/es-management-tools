# ES Management Tools & Fault Diagnosis System

## Overview
This is a comprehensive **Elasticsearch fault diagnosis and cluster management project** with real production experience. The project contains not only management tools but also proven fault analysis methodologies and battle-tested troubleshooting capabilities.

## 🚨 Core Value: ES Fault Diagnosis Expert System
This project demonstrates advanced ES troubleshooting capabilities with real case studies and proven solutions.

## Core Scripts

### 1. es_manager.py - ES集群管理工具
**功能**: 综合的Elasticsearch集群管理和监控工具
**主要功能**:
- 🔍 集群健康状态检查 (集群状态、节点数、分片统计)
- 📋 索引信息查询 (按大小排序，支持日期过滤)
- 🔧 分片信息查询 (详细分片状态，按日期查询)
- 🖥️ 系统资源统计 (CPU、内存、磁盘使用率，带告警)

**使用方法**:
```bash
# 交互模式
python3 es_manager.py

# 指定ES地址
python3 es_manager.py http://192.168.0.93:9201
```

**菜单选项**:
- 1: 集群健康状态检查
- 2: 索引信息查询 (按大小排序)
- 3: 分片信息查询 (支持日期)
- 4: 系统资源统计 (CPU/内存/磁盘)

### 2. SMS验证码查询工具 (两个版本)

#### sms_query.py (Python版本 - 推荐)
**功能**: 通过手机号查询过去15分钟内的验证码短信
**主要功能**:
- 📱 手机号格式验证 (中国11位手机号)
- ⏰ 时间窗口查询 (过去15分钟)
- 🔍 智能验证码提取 (支持多种验证码格式)
- 📊 结果格式化显示
- 🔄 交互模式支持

**使用方法**:
```bash
# 交互模式
python3 sms_query.py

# 直接查询
python3 sms_query.py 18727448600
```

#### sms_quick (轻量版本 - 分发推荐)
**功能**: 轻量级SMS查询工具，适合分发给其他人
**优势**:
- 🚀 基本无依赖，仅需Python3(系统自带)
- 📦 单文件分发，开箱即用
- 🎯 专注验证码查询功能
- ✅ 查询稳定，成功率高

**使用方法**:
```bash
# 直接查询
./sms_quick 18727448600
```

**数据结构**: 
- 查询索引: `*message-center*`
- 数据路径: `msgObj.object.requestBody` (JSON格式)
- 短信内容: `requestBody.content`
- 接收者: `requestBody.receiver`

### 3. start.sh - 启动脚本
**功能**: 环境检查和依赖安装
**主要功能**:
- ✅ Python环境检查
- 📦 依赖安装 (requests>=2.25.0)
- 🚀 工具启动选择

**使用方法**:
```bash
./start.sh
```

## ES Connection
- **Default URL**: http://192.168.0.93:9201/
- **Index Pattern**: logstash-loghub-{type}-{service}-{environment}-{date}
- **SMS Indexes**: *message-center*

## Technical Details

### ES Manager 功能详情
1. **集群健康检查**: 显示集群状态、节点数、分片统计，包含今日数据统计
2. **索引查询**: 支持日期过滤，按存储大小降序排列，显示分片数和文档数
3. **分片查询**: 详细分片信息，状态统计，TOP5服务统计
4. **系统监控**: CPU/内存/磁盘使用率，带颜色告警（正常/较高/过高）

### SMS Query 功能详情
1. **时间处理**: UTC时间转换，15分钟滚动窗口
2. **验证码提取**: 支持多种格式（"验证码：1234"、"验证码是1234"、"code: 1234"等）
3. **错误处理**: 网络超时、ES查询失败、字段映射错误等
4. **数据解析**: 深度解析ES复杂JSON结构，提取嵌套字段

## Dependencies
- requests>=2.25.0
- Python 3.6+

## Usage Examples

### 查询今天的索引信息
```bash
python3 es_manager.py
# 选择 2 -> 回车使用默认今天日期
```

### 查询特定日期的分片信息
```bash
python3 es_manager.py  
# 选择 3 -> 输入 2025-07-06
```

### 查询手机验证码
```bash
python3 sms_query.py 18727448600
# 输出: 验证码、时间、短信内容
```

## File Structure
```
es/
├── es_manager.py        # ES集群管理工具
├── sms_query.py         # SMS查询工具 (Linux/macOS完整版)
├── sms_quick           # SMS查询工具 (Linux/macOS轻量版)
├── sms_windows.py      # SMS查询工具 (Windows版本)
├── sms_windows.bat     # SMS查询工具 (Windows批处理版)
├── start.sh            # 启动脚本 (Linux/macOS)
├── requirements.txt    # Python依赖
├── SMS使用说明.md       # Linux/macOS使用说明
├── Windows使用说明.md   # Windows使用说明
└── CLAUDE.md          # 完整项目文档
```

### 4. Windows版本支持

#### sms_windows.py (Windows兼容版)
**功能**: 专为Windows系统设计的SMS查询工具
**优势**:
- 🪟 Windows全版本兼容 (Win7/8/10/11)
- 🐍 仅需Python标准库，无需额外安装
- 🎯 功能完整，支持交互模式
- 📦 单文件分发

**使用方法**:
```cmd
# Windows命令行
python sms_windows.py 18727448600

# 交互模式
python sms_windows.py
```

#### sms_windows.bat (批处理版)
**功能**: Windows批处理文件，双击运行
**优势**:
- 🚀 双击即用，无需命令行
- 👥 适合普通用户
- 📝 自动输入提示

## Best Practices

### 按操作系统选择
1. **Linux/macOS**: 使用 `sms_query.py` (完整功能) 或 `sms_quick` (轻量)
2. **Windows**: 使用 `sms_windows.py` (Python) 或 `sms_windows.bat` (批处理)
3. **跨平台分发**: 提供完整工具包，包含所有版本

### 按用户类型选择
1. **技术人员**: Python版本 (`sms_query.py`, `sms_windows.py`)
2. **普通用户**: 轻量版本 (`sms_quick`, `sms_windows.bat`)
3. **系统管理员**: ES Manager (`es_manager.py`)

## Notes
- 所有工具都是只读操作，不会修改ES数据
- SMS查询工具专门针对message-center索引的数据结构优化
- ES Manager支持多种日期格式查询，灵活性强
- 所有脚本都包含完整的错误处理和用户友好提示

---

## 🔥 ES故障排查与诊断能力 (核心价值)

### 实战故障案例
本项目包含真实的生产环境ES故障排查经验，包括完整的故障分析报告：

**重大故障案例 - 2025年7月ES集群攻击事件**:
- **故障现象**: 集群RED状态，15,000+分片未分配，连续两日故障
- **表面现象**: 似乎是外部ES 5.0版本客户端攻击
- **深层原因**: 内部遗留服务`erlangshen`使用ES 5.0客户端持续连接ES 7.6.2集群
- **技术链路**: 协议不兼容 → 异常对象创建 → 内存压力 → GC风暴 → 集群分区
- **解决方案**: 识别并停止遗留服务，集群自动恢复

### 故障诊断方法论

#### 1. 系统性故障分析流程
```
1. 现象观察 → 2. 日志分析 → 3. 性能指标 → 4. 根因定位 → 5. 解决验证
```

#### 2. 核心诊断技能
- **GC日志精确分析**: 精确到毫秒级的GC停顿时间分析
- **网络协议层诊断**: ES版本兼容性、传输层异常分析  
- **内存分配路径追踪**: 代码级别的对象创建链路分析
- **集群分区根因分析**: 从网络到应用层的完整分析链路

#### 3. 高级诊断技术
- **异常日志关联分析**: 从传输层日志发现攻击模式
- **GC性能调优**: G1GC参数优化，减少停顿时间
- **集群容错增强**: 故障检测超时调优，提高容错能力
- **安全攻击识别**: 区分恶意攻击与配置错误

### 常见ES故障模式与解决方案

#### 故障模式1: GC风暴导致集群分区
**症状**: 节点频繁离线，大量分片未分配
```bash
# 诊断命令
grep "GC" /var/log/elasticsearch/*.log | tail -20
curl -s "http://es-host:9200/_nodes/stats/jvm"
```
**解决方案**: JVM调优 + 故障检测参数调优

#### 故障模式2: 版本兼容性攻击
**症状**: `unsupported version` 大量出现，内存使用增长
```bash
# 诊断命令  
grep "unsupported version" /var/log/elasticsearch/*.log
netstat -antup | grep 9300
```
**解决方案**: 识别攻击源 + 网络防护 + 客户端升级

#### 故障模式3: 分片分配异常
**症状**: 集群RED/YELLOW状态，分片无法分配
```bash
# 诊断命令
curl -s "http://es-host:9200/_cluster/allocation/explain?pretty"
curl -s "http://es-host:9200/_cat/shards?v&h=index,shard,prirep,state,unassigned.reason"
```

### 监控与预防体系

#### 1. 关键监控指标
- **GC监控**: 停顿时间、频率、内存回收效率
- **集群健康**: 节点状态、分片分配、集群状态
- **网络安全**: 异常连接、协议版本检查
- **性能指标**: CPU、内存、磁盘、网络IO

#### 2. 告警触发条件
```bash
# GC停顿告警
GC停顿时间 > 100ms

# 集群状态告警  
集群状态 != GREEN

# 安全告警
"unsupported version" 检测
```

#### 3. 自动化防护
- IP黑名单自动更新
- 连接频率限制
- 协议版本检查
- 集群故障自动恢复

### 技术债务识别能力
- 遗留服务管理漏洞识别
- 版本升级流程缺陷发现  
- 监控盲点识别与补充
- 安全防护薄弱环节分析

### 实战工具集成
- **es_manager.py**: 集群健康诊断、分片状态分析
- **故障分析报告**: 完整的故障排查文档和解决方案
- **监控脚本**: 自动化监控和告警脚本
- **防护措施**: iptables规则、JVM调优参数

### 项目文档结构
```
20250709故障分析报告/              # 真实故障案例分析
├── ES集群故障综合分析报告_最终版.md    # 完整故障分析报告  
├── ES集群5.0版本攻击事件分析报告.md    # 攻击事件深度分析
├── es执行完的命令.txt              # 故障排查命令记录
└── greencloud-log-center-*.log     # 原始故障日志

gc-cls/                           # CLS日志系统分析
├── 故障排查文档.md                 # 系统故障排查方法
├── 性能优化方案.md                 # 性能调优建议  
└── 监控告警设计.md                 # 监控体系设计
```

**总结**: 这是一个具备企业级ES故障诊断能力的实战项目，不仅包含管理工具，更重要的是沉淀了完整的故障分析方法论和实战经验。

---

## 🚀 快速开始指南

### 故障排查场景
当ES集群出现问题时，按以下顺序进行诊断：

1. **集群健康检查**
```bash
python3 es_manager.py
# 选择 1 - 查看集群整体状态
```

2. **索引状态分析** 
```bash
python3 es_manager.py  
# 选择 2 - 查看索引大小和状态
```

3. **分片分配诊断**
```bash
python3 es_manager.py
# 选择 3 - 查看分片分配状态
```

4. **系统资源检查**
```bash
python3 es_manager.py
# 选择 4 - 查看CPU/内存/磁盘状态
```

### 业务功能验证
验证业务数据是否正常写入：
```bash
python3 sms_query.py 手机号
# 验证短信数据是否能正常查询
```

### 故障分析参考
- 查看 `20250709故障分析报告/` 目录了解完整的故障排查案例
- 参考 `ES集群故障综合分析报告_最终版.md` 学习系统性故障分析方法
- 查看 `gc-cls/` 目录了解CLS日志系统的故障排查经验

### 重要提醒
- 所有工具都是只读操作，安全可靠
- 工具已经过生产环境验证，可放心使用
- 遇到复杂故障时，参考已有的故障案例分析报告
- 优先使用系统性的故障分析方法，避免盲目排查

---

# important-instruction-reminders
Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.