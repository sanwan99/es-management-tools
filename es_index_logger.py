#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ES索引监控记录工具
基于es_manager.py的索引查询功能，将结果追加到MD文档中
"""

import json
import requests
import os
import sys
from datetime import datetime, timedelta
from typing import List, Dict, Any
import calendar
import re

class ESIndexLogger:
    def __init__(self, es_url: str = "http://192.168.0.93:9201"):
        self.es_url = es_url.rstrip('/')
        self.md_file = "es_index_monitor.md"
    
    def make_request(self, endpoint: str, method: str = "GET", data: dict = None, return_json: bool = True):
        """发送 HTTP 请求到 ES"""
        url = f"{self.es_url}/{endpoint}"
        try:
            if method == "GET":
                response = requests.get(url, timeout=30)
            elif method == "POST":
                response = requests.post(url, json=data, timeout=30)
            else:
                raise ValueError(f"不支持的 HTTP 方法: {method}")
            
            response.raise_for_status()
            
            if return_json:
                return response.json()
            else:
                return response.text
        except requests.exceptions.RequestException as e:
            print(f"请求失败: {e}")
            return {} if return_json else ""
    
    def convert_size_to_gb(self, size_str: str) -> float:
        """转换存储大小字符串到GB"""
        if not size_str or size_str == "0":
            return 0.0
        
        size_str = size_str.lower().strip()
        if size_str.endswith('gb'):
            return float(size_str[:-2])
        elif size_str.endswith('mb'):
            return float(size_str[:-2]) / 1024
        elif size_str.endswith('kb'):
            return float(size_str[:-2]) / (1024 * 1024)
        elif size_str.endswith('b'):
            return float(size_str[:-1]) / (1024 * 1024 * 1024)
        else:
            try:
                return float(size_str) / (1024 * 1024 * 1024)
            except:
                return 0.0
    
    def get_weekday_name(self, date_str: str) -> str:
        """获取日期对应的中文星期名称"""
        try:
            date_obj = datetime.strptime(date_str, "%Y-%m-%d")
            weekdays = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]
            return weekdays[date_obj.weekday()]
        except:
            return ""
    
    def get_indices_data(self, pattern: str = None) -> Dict[str, Any]:
        """获取索引数据"""
        # 默认查询今天的索引
        if pattern is None:
            today = datetime.now().strftime("%Y-%m-%d")
            pattern = f"*{today}*"
            query_date = today
        else:
            # 从pattern中提取日期
            date_match = re.search(r'(\d{4}-\d{2}-\d{2})', pattern)
            query_date = date_match.group(1) if date_match else datetime.now().strftime("%Y-%m-%d")
        
        try:
            # 获取JSON格式的索引信息，按存储大小降序排列
            indices_data = self.make_request(f"_cat/indices/{pattern}?format=json&h=index,pri,rep,docs.count,store.size&s=store.size:desc")
            if not indices_data:
                return {"error": "无法获取索引数据"}
            
            # 处理数据
            processed_data = []
            for idx in indices_data:
                index_name = idx.get('index', 'N/A')
                size_str = idx.get('store.size', '0')
                size_gb = self.convert_size_to_gb(size_str)
                primary_shards = int(idx.get('pri', 0))
                replica_shards = int(idx.get('rep', 0))
                total_shards = primary_shards + replica_shards
                docs_count = int(idx.get('docs.count', 0))
                
                processed_data.append({
                    'index': index_name,
                    'size_gb': size_gb,
                    'shards': total_shards,
                    'docs': docs_count
                })
            
            # 统计总计
            total_size = sum(item['size_gb'] for item in processed_data)
            total_docs = sum(item['docs'] for item in processed_data)
            total_shards = sum(item['shards'] for item in processed_data)
            
            return {
                'date': query_date,
                'query_time': datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                'total_indices': len(processed_data),
                'total_size_gb': total_size,
                'total_shards': total_shards,
                'total_docs': total_docs,
                'indices': processed_data
            }
            
        except Exception as e:
            return {"error": f"查询索引信息失败: {e}"}
    
    def create_md_header_if_not_exists(self):
        """如果MD文件不存在，创建文件头"""
        if not os.path.exists(self.md_file):
            header = """# ES索引监控记录

> 本文档记录Elasticsearch集群的索引监控数据  
> 自动生成时间: {datetime}  
> 集群地址: {es_url}

""".format(
                datetime=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                es_url=self.es_url
            )
            with open(self.md_file, 'w', encoding='utf-8') as f:
                f.write(header)
    
    def append_to_md(self, data: Dict[str, Any]):
        """将数据追加到MD文档"""
        if 'error' in data:
            print(f"❌ {data['error']}")
            return
        
        # 确保MD文件存在
        self.create_md_header_if_not_exists()
        
        # 准备MD内容
        weekday = self.get_weekday_name(data['date'])
        date_display = f"{data['date']} ({weekday})" if weekday else data['date']
        
        md_content = f"""## {date_display}
**查询时间**: {data['query_time']}  
**总索引数**: {data['total_indices']}个  
**总大小**: {data['total_size_gb']:.2f} GB  
**总分片**: {data['total_shards']}个  
**总文档**: {data['total_docs']:,}个  

### TOP 20 索引 (按大小排序)
| 排名 | 索引名称 | 大小(GB) | 分片数 | 文档数 |
|------|----------|----------|--------|--------|
"""
        
        # 添加TOP20索引数据
        for i, idx in enumerate(data['indices'][:20], 1):
            # 使用完整的索引名称，不进行截断
            display_name = idx['index']
            md_content += f"| {i} | {display_name} | {idx['size_gb']:.2f} | {idx['shards']} | {idx['docs']:,} |\n"
        
        # 如果还有更多索引，显示省略信息
        if len(data['indices']) > 20:
            remaining = len(data['indices']) - 20
            md_content += f"\n*... 还有 {remaining} 个索引（按大小降序排列）*\n"
        
        md_content += "\n---\n\n"
        
        # 追加到文件
        with open(self.md_file, 'a', encoding='utf-8') as f:
            f.write(md_content)
        
        print(f"✅ 数据已成功追加到 {self.md_file}")
        print(f"📊 记录: {data['total_indices']}个索引, {data['total_size_gb']:.2f}GB, {data['total_docs']:,}个文档")
    
    def parse_latest_date_from_md(self) -> str:
        """解析MD文件获取最新日期"""
        if not os.path.exists(self.md_file):
            return None
        
        try:
            with open(self.md_file, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # 查找所有日期格式 ## YYYY-MM-DD
            date_pattern = r'## (\d{4}-\d{2}-\d{2})'
            dates = re.findall(date_pattern, content)
            
            if not dates:
                return None
            
            # 返回最新的日期（按字符串排序，日期格式YYYY-MM-DD可以直接排序）
            return max(dates)
            
        except Exception as e:
            print(f"❌ 解析MD文件失败: {e}")
            return None
    
    def generate_missing_dates(self, start_date: str) -> List[str]:
        """生成从start_date到今天之间缺失的日期列表"""
        try:
            start_dt = datetime.strptime(start_date, "%Y-%m-%d")
            today_dt = datetime.now()
            
            missing_dates = []
            current_dt = start_dt + timedelta(days=1)  # 从start_date的下一天开始
            
            while current_dt.date() <= today_dt.date():
                missing_dates.append(current_dt.strftime("%Y-%m-%d"))
                current_dt += timedelta(days=1)
            
            return missing_dates
            
        except Exception as e:
            print(f"❌ 生成日期列表失败: {e}")
            return []
    
    def batch_append_missing_dates(self):
        """批量查询并追加缺失日期的数据"""
        print("🔍 正在检查缺失的日期...")
        
        # 获取MD文件中的最新日期
        latest_date = self.parse_latest_date_from_md()
        if not latest_date:
            print("❌ 无法从MD文件中找到日期信息，请先手动添加一条记录")
            return
        
        print(f"📅 MD文件中最新日期: {latest_date}")
        
        # 生成缺失的日期列表
        missing_dates = self.generate_missing_dates(latest_date)
        if not missing_dates:
            print("✅ 没有缺失的日期，所有数据都是最新的")
            return
        
        print(f"📋 发现 {len(missing_dates)} 个缺失日期: {missing_dates[0]} 到 {missing_dates[-1]}")
        
        # 确认是否继续
        confirm = input("是否继续补充这些日期的数据? (y/N): ").strip().lower()
        if confirm not in ['y', 'yes']:
            print("❌ 操作已取消")
            return
        
        # 批量查询并追加
        success_count = 0
        failed_dates = []
        
        for i, date in enumerate(missing_dates, 1):
            print(f"\n🔍 [{i}/{len(missing_dates)}] 正在查询 {date} 的索引...")
            
            pattern = f"*{date}*"
            data = self.get_indices_data(pattern)
            
            if 'error' in data:
                print(f"❌ {date}: {data['error']}")
                failed_dates.append(date)
            else:
                self.append_to_md(data)
                success_count += 1
        
        # 显示总结
        print("\n" + "="*60)
        print(f"✅ 补充完成! 成功: {success_count}个, 失败: {len(failed_dates)}个")
        if failed_dates:
            print(f"❌ 失败的日期: {', '.join(failed_dates)}")
        print("="*60)
    
    def interactive_mode(self):
        """交互模式"""
        print("🚀 ES索引监控记录工具")
        print(f"连接地址: {self.es_url}")
        print(f"输出文件: {self.md_file}")
        print("-" * 60)
        
        while True:
            print("\n📋 请选择操作:")
            print("1. 查询今天的索引并追加到MD")
            print("2. 查询指定日期的索引并追加到MD")
            print("3. 自动补充缺失日期的数据")
            print("4. 查看MD文档内容")
            print("0. 退出")
            
            try:
                choice = input("请选择 [0-4]: ").strip()
                
                if choice == "0":
                    print("👋 再见!")
                    break
                elif choice == "1":
                    print("🔍 正在查询今天的索引...")
                    data = self.get_indices_data()
                    self.append_to_md(data)
                elif choice == "2":
                    date_input = input("请输入日期 (格式: YYYY-MM-DD): ").strip()
                    if not date_input:
                        print("❌ 日期不能为空")
                        continue
                    
                    # 验证日期格式
                    try:
                        datetime.strptime(date_input, "%Y-%m-%d")
                    except ValueError:
                        print("❌ 日期格式错误，请使用 YYYY-MM-DD 格式")
                        continue
                    
                    pattern = f"*{date_input}*"
                    print(f"🔍 正在查询 {date_input} 的索引...")
                    data = self.get_indices_data(pattern)
                    self.append_to_md(data)
                elif choice == "3":
                    self.batch_append_missing_dates()
                elif choice == "4":
                    if os.path.exists(self.md_file):
                        print(f"📄 MD文档内容预览 ({self.md_file}):")
                        print("=" * 60)
                        with open(self.md_file, 'r', encoding='utf-8') as f:
                            content = f.read()
                            # 显示前500个字符
                            if len(content) > 500:
                                print(content[:500] + "...")
                                print(f"\n... 文档共 {len(content)} 字符，完整内容请查看文件")
                            else:
                                print(content)
                    else:
                        print("❌ MD文档不存在")
                else:
                    print("❌ 无效选择，请重新输入")
                
                if choice in ["1", "2", "3", "4"]:
                    input("\n按回车键继续...")
                
            except KeyboardInterrupt:
                print("\n👋 再见!")
                break
            except Exception as e:
                print(f"❌ 发生错误: {e}")
                input("按回车键继续...")

def main():
    """主函数"""
    if len(sys.argv) > 1:
        es_url = sys.argv[1]
    else:
        es_url = "http://192.168.0.93:9201"
    
    logger = ESIndexLogger(es_url)
    
    try:
        # 测试连接
        health = logger.make_request("_cluster/health")
        if not health:
            print(f"❌ 无法连接到 Elasticsearch: {es_url}")
            return
        
        # 如果提供了第二个参数作为日期，直接查询并追加
        if len(sys.argv) > 2:
            date_param = sys.argv[2]
            try:
                datetime.strptime(date_param, "%Y-%m-%d")
                pattern = f"*{date_param}*"
                print(f"🔍 查询 {date_param} 的索引...")
                data = logger.get_indices_data(pattern)
                logger.append_to_md(data)
            except ValueError:
                print("❌ 日期格式错误，请使用 YYYY-MM-DD 格式")
        else:
            logger.interactive_mode()
            
    except Exception as e:
        print(f"❌ 启动失败: {e}")

if __name__ == "__main__":
    main()