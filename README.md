# ES Management Tools & Fault Diagnosis System

> 🚀 **企业级Elasticsearch集群管理工具集**  
> 专业的ES故障诊断与监控解决方案，具备真实生产环境实战经验

[![Python](https://img.shields.io/badge/Python-3.6+-blue.svg)](https://python.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![ES Version](https://img.shields.io/badge/Elasticsearch-7.x-orange.svg)](https://www.elastic.co/)

## 🌟 项目亮点

- **🔍 专业ES集群管理** - 完整的集群健康检查、索引管理、分片分析
- **📊 智能监控记录** - 自动化索引监控，支持历史数据补充功能
- **🔧 故障诊断专家系统** - 基于真实生产环境故障排查经验
- **📱 SMS验证码查询** - 高效的短信验证码检索工具
- **⚡ 一键启动** - 智能启动脚本，自动环境检查和依赖安装

## 📁 项目结构

```
es-management-tools/
├── 📄 es_manager.py           # ES集群管理核心工具
├── 📄 es_index_logger.py      # 索引监控记录工具 (含自动补充功能)
├── 📄 sms_query.py            # SMS验证码查询工具
├── 📄 start.sh                # 智能启动脚本
├── 📄 requirements.txt        # Python依赖包
├── 📁 es定时任务/              # ES自动化运维脚本
├── 📁 es索引模板/              # 索引模板优化方案
├── 📄 CLAUDE.md               # 完整项目文档
└── 📄 README.md               # 项目说明
```

## 🚀 快速开始

### 环境要求
- Python 3.6+
- 网络访问Elasticsearch集群
- Linux/macOS/Windows (WSL)

### 安装使用

```bash
# 1. 克隆项目
git clone https://github.com/sanwan99/es-management-tools.git
cd es-management-tools

# 2. 一键启动 (自动检查环境和安装依赖)
./start.sh

# 3. 或手动安装依赖
pip3 install -r requirements.txt
python3 es_manager.py
```

## 🛠️ 核心功能

### 1. ES集群管理工具 (`es_manager.py`)

**🔍 集群健康诊断**
- 集群状态检查 (GREEN/YELLOW/RED)
- 节点数量和分片统计
- 实时资源使用情况

**📋 索引信息查询**
- 按存储大小排序显示
- 支持日期过滤查询
- 分片数和文档数统计

**🔧 分片状态分析**
- 详细分片分配状态
- 未分配分片诊断
- TOP服务统计分析

**🖥️ 系统资源监控**
- CPU/内存/磁盘使用率
- 彩色告警显示 (正常/告警/危险)
- 实时性能指标

```bash
# 使用示例
python3 es_manager.py                    # 交互模式
python3 es_manager.py http://es-host:9200  # 指定ES地址
```

### 2. 索引监控记录工具 (`es_index_logger.py`) ⭐

**📊 自动化监控记录**
- 生成Markdown格式监控报告
- 索引大小、分片数、文档数统计
- TOP 20索引排行榜

**🔄 智能数据补充** (新功能)
- 自动检测MD文件中的最新记录日期
- 一键补充缺失日期的历史数据
- 批量查询，进度显示

**📅 灵活查询模式**
- 查询今天的索引数据
- 指定日期查询
- 查看历史监控记录

```bash
# 使用示例
python3 es_index_logger.py              # 交互模式
python3 es_index_logger.py http://es-host:9200 2025-07-28  # 直接查询指定日期
```

**自动补充示例**:
```
📅 MD文件中最新日期: 2025-07-20
📋 发现 7 个缺失日期: 2025-07-21 到 2025-07-27
✅ 补充完成! 成功: 7个, 失败: 0个
```

### 3. SMS验证码查询工具 (`sms_query.py`)

**📱 智能验证码提取**
- 支持11位中国手机号验证
- 过去15分钟时间窗口查询
- 多种验证码格式识别

**⚡ 高效查询**
- 针对message-center索引优化
- 深度JSON结构解析
- 完善的错误处理

```bash
# 使用示例
python3 sms_query.py 18612345678      # 直接查询
python3 sms_query.py                  # 交互模式
```

### 4. 智能启动脚本 (`start.sh`)

**🔧 一键启动**
- 自动Python环境检查
- 智能依赖安装
- 多模式选择菜单

**🔍 环境快速查询**
- 支持按环境关键词查询 (prd/dev/test)
- 实时索引和分片统计
- 彩色状态显示

```bash
./start.sh                           # 交互菜单
./start.sh http://es-host:9200        # 直接启动ES管理工具
```

## 📊 监控报告示例

生成的监控报告格式：

```markdown
## 2025-07-28 (星期一)
**查询时间**: 2025-07-28 10:30:15
**总索引数**: 125个
**总大小**: 89.45 GB
**总分片**: 250个
**总文档**: 1,234,567个

### TOP 20 索引 (按大小排序)
| 排名 | 索引名称 | 大小(GB) | 分片数 | 文档数 |
|------|----------|----------|--------|--------|
| 1 | logstash-app-prd-2025-07-28 | 15.23 | 5 | 987,654 |
| 2 | logstash-api-prd-2025-07-28 | 12.45 | 5 | 756,432 |
...
```

## ⚙️ 配置说明

### 默认配置
```python
# ES连接地址
ES_URL = "http://192.168.0.93:9201"

# SMS查询索引模式
SMS_INDEX_PATTERN = "*message-center*"

# 监控输出文件
MONITOR_OUTPUT = "es_index_monitor.md"
```

### 环境变量支持
```bash
export ES_HOST="http://your-es-host:9200"
export SMS_INDEX="your-sms-index*"
```

## 🔧 高级功能

### 批量操作
```bash
# 批量查询多个日期
for date in 2025-07-{20..27}; do
    python3 es_index_logger.py http://es-host:9200 $date
done
```

### 定时任务集成
```bash
# 添加到crontab - 每日凌晨1点自动记录
0 1 * * * cd /path/to/es-tools && python3 es_index_logger.py
```

## 🛡️ 故障诊断能力

> 本项目包含丰富的企业级ES故障排查经验，虽然详细的故障分析报告因包含敏感信息未开源，但工具本身集成了完整的诊断方法论。

**故障排查流程**:
1. **集群健康检查** → 识别整体状态
2. **索引状态分析** → 定位问题索引  
3. **分片分配诊断** → 分析分片异常
4. **系统资源检查** → 确认资源瓶颈

**支持的故障场景**:
- 集群RED/YELLOW状态诊断
- 分片未分配问题排查
- 索引大小异常监控
- 性能瓶颈识别

## 📈 最佳实践

### 日常监控
1. **每日索引检查**: 使用`es_index_logger.py`记录关键指标
2. **定期健康检查**: 运行`es_manager.py`检查集群状态
3. **历史数据补充**: 利用自动补充功能维护完整监控记录

### 故障应急
1. **快速状态检查**: `./start.sh` → 选择完整ES管理工具
2. **重点索引分析**: 按日期查询异常时段的索引状态
3. **系统资源确认**: 检查CPU/内存/磁盘使用情况

## 🤝 贡献指南

欢迎提交Issue和Pull Request！

1. Fork 项目
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 开启Pull Request

## 📝 更新日志

### v1.2.0 (2025-07-28)
- ✨ 新增索引监控自动补充缺失日期功能
- 🔧 优化启动脚本环境检查逻辑
- 📊 改进监控报告格式和统计精度

### v1.1.0
- ✨ 添加SMS验证码查询工具
- 🔧 集成智能启动脚本
- 📈 完善集群健康检查功能

### v1.0.0
- 🎉 初始版本发布
- ✨ ES集群管理核心功能
- 📊 索引监控记录功能

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情

## 👨‍💻 作者

**sanwan99**
- GitHub: [@sanwan99](https://github.com/sanwan99)
- Email: 1055480743@qq.com

## 🙏 致谢

- 感谢Elasticsearch社区的技术支持
- 感谢所有贡献者的努力
- 基于真实生产环境实战经验打造

---

⭐ **如果这个项目对你有帮助，请给个Star支持一下！**