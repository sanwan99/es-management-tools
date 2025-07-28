#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Elasticsearch 管理工具
提供集群状态检查、索引查询、分片信息等功能
"""

import json
import requests
import os
import sys
from datetime import datetime, timedelta
from typing import List, Dict, Any
import re

class ESManager:
    def __init__(self, es_url: str = "http://192.168.0.93:9201"):
        self.es_url = es_url.rstrip('/')
        self.cache_file = ".es_indices_cache.json"
        self.indices_cache = self.load_indices_cache()
    
    def load_indices_cache(self) -> Dict[str, Any]:
        """加载本地缓存的索引信息"""
        if os.path.exists(self.cache_file):
            try:
                with open(self.cache_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                print(f"加载缓存失败: {e}")
        return {"indices": [], "last_update": ""}
    
    def save_indices_cache(self, indices: List[str]):
        """保存索引信息到本地缓存"""
        cache_data = {
            "indices": indices,
            "last_update": datetime.now().isoformat()
        }
        try:
            with open(self.cache_file, 'w', encoding='utf-8') as f:
                json.dump(cache_data, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"保存缓存失败: {e}")
    
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
    
    def check_cluster_health(self):
        """检查集群健康状态"""
        print("=" * 60)
        print("🔍 集群健康状态检查")
        print("=" * 60)
        
        health = self.make_request("_cluster/health")
        if not health:
            return
        
        status_colors = {
            "green": "🟢",
            "yellow": "🟡", 
            "red": "🔴"
        }
        
        print(f"集群状态: {status_colors.get(health.get('status', 'unknown'), '⚪')} {health.get('status', 'unknown').upper()}")
        print(f"集群名称: {health.get('cluster_name', 'N/A')}")
        print(f"节点数量: {health.get('number_of_nodes', 0)}")
        print(f"数据节点: {health.get('number_of_data_nodes', 0)}")
        print(f"活跃分片: {health.get('active_shards', 0)}")
        print(f"主分片: {health.get('active_primary_shards', 0)}")
        print(f"重定位分片: {health.get('relocating_shards', 0)}")
        print(f"初始化分片: {health.get('initializing_shards', 0)}")
        print(f"未分配分片: {health.get('unassigned_shards', 0)}")
        
        if health.get('unassigned_shards', 0) > 0:
            print("⚠️  警告: 存在未分配的分片")
            
        # 添加今天的索引和分片统计
        self.show_today_stats()
    
    def show_today_stats(self):
        """显示今天的索引和分片统计"""
        today = datetime.now().strftime("%Y-%m-%d")
        print(f"\n📅 今日统计 ({today}):")
        print("-" * 40)
        
        try:
            # 获取今天的索引
            indices_response = self.make_request(f"_cat/indices/*{today}*?format=json")
            if indices_response:
                total_indices = len(indices_response)
                
                # 统计不同类型的索引
                logs_count = len([idx for idx in indices_response if 'logstash-loghub-logs-' in idx.get('index', '')])
                error_count = len([idx for idx in indices_response if 'logstash-loghub-error-' in idx.get('index', '')])
                
                print(f"📋 索引总数: {total_indices}")
                print(f"   ├─ 日志索引: {logs_count}")
                print(f"   └─ 错误索引: {error_count}")
                
                # 统计文档数和存储大小
                total_docs = sum(int(idx.get('docs.count', 0)) for idx in indices_response if idx.get('docs.count', '0').isdigit())
                print(f"📄 文档总数: {total_docs:,}")
                
            # 获取今天的分片信息
            shards_response = self.make_request(f"_cat/shards/*{today}*?format=json")
            if shards_response:
                total_shards = len(shards_response)
                primary_shards = len([s for s in shards_response if s.get('prirep') == 'p'])
                replica_shards = len([s for s in shards_response if s.get('prirep') == 'r'])
                
                print(f"🔧 分片总数: {total_shards}")
                print(f"   ├─ 主分片: {primary_shards}")
                print(f"   └─ 副本分片: {replica_shards}")
                
                # 分片状态统计
                states = {}
                for shard in shards_response:
                    state = shard.get('state', 'unknown')
                    states[state] = states.get(state, 0) + 1
                
                if len(states) > 1 or 'STARTED' not in states:
                    print("🔍 分片状态:")
                    for state, count in states.items():
                        emoji = "✅" if state == "STARTED" else "⚠️"
                        print(f"   {emoji} {state}: {count}")
                else:
                    print("✅ 所有分片状态正常")
                    
        except Exception as e:
            print(f"❌ 获取今日统计失败: {e}")
    
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
            # 尝试直接转换为数字（假设是字节）
            try:
                return float(size_str) / (1024 * 1024 * 1024)
            except:
                return 0.0
    
    def get_indices_info(self, pattern: str = None, refresh_cache: bool = False):
        """获取索引信息"""
        print("=" * 60)
        print("📋 索引信息查询")
        print("=" * 60)
        
        # 默认查询今天的索引
        if pattern is None:
            today = datetime.now().strftime("%Y-%m-%d")
            pattern = f"*{today}*"
            print(f"查询今天的索引: {today}")
        else:
            print(f"查询模式: {pattern}")
        
        try:
            # 获取JSON格式的索引信息，按存储大小降序排列
            indices_data = self.make_request(f"_cat/indices/{pattern}?format=json&h=index,pri,rep,docs.count,store.size&s=store.size:desc")
            if not indices_data:
                print("❌ 无法获取索引数据")
                return
            
            print(f"\n找到 {len(indices_data)} 个索引:")
            print("=" * 100)
            print(f"{'序号':<4} {'索引名称':<60} {'大小(GB)':<12} {'分片数':<8} {'文档数':<15}")
            print("=" * 100)
            
            for i, idx in enumerate(indices_data, 1):
                index_name = idx.get('index', 'N/A')
                size_str = idx.get('store.size', '0')
                size_gb = self.convert_size_to_gb(size_str)
                primary_shards = int(idx.get('pri', 0))
                replica_shards = int(idx.get('rep', 0))
                total_shards = primary_shards + replica_shards
                docs_count = int(idx.get('docs.count', 0))
                
                # 截断过长的索引名称
                display_name = index_name[:60] if len(index_name) > 60 else index_name
                
                print(f"{i:<4} {display_name:<60} {size_gb:>10.2f}  {total_shards:>6}   {docs_count:>13,}")
                
                # 只显示前20个，避免输出过多
                if i >= 20:
                    remaining = len(indices_data) - 20
                    if remaining > 0:
                        print(f"... 还有 {remaining} 个索引（按大小降序排列）")
                    break
            
            print("=" * 100)
            
            # 统计总计
            total_size = sum(self.convert_size_to_gb(idx.get('store.size', '0')) for idx in indices_data)
            total_docs = sum(int(idx.get('docs.count', 0)) for idx in indices_data)
            total_shards = sum(int(idx.get('pri', 0)) + int(idx.get('rep', 0)) for idx in indices_data)
            
            print(f"📊 总计: {len(indices_data)} 个索引, {total_size:.2f} GB, {total_shards} 个分片, {total_docs:,} 个文档")
            
        except Exception as e:
            print(f"❌ 查询索引信息失败: {e}")
    
    def get_shards_info(self, date_pattern: str = None):
        """获取分片信息"""
        print("=" * 60)
        print("🔧 分片信息查询")
        print("=" * 60)
        
        if not date_pattern:
            today = datetime.now().strftime("%Y-%m-%d")
            date_pattern = today
        
        index_pattern = f"*{date_pattern}*"
        print(f"查询日期: {date_pattern}")
        
        try:
            # 获取JSON格式的分片信息
            shards_data = self.make_request(f"_cat/shards/{index_pattern}?format=json&h=index,shard,prirep,state,docs,store,node")
            if not shards_data:
                print("❌ 无法获取分片数据")
                return
            
            print(f"\n找到 {len(shards_data)} 个分片:")
            print("=" * 120)
            print(f"{'索引名称':<50} {'分片':<4} {'类型':<4} {'状态':<8} {'文档数':<12} {'大小':<10} {'节点':<15}")
            print("=" * 120)
            
            # 按索引和分片号排序
            sorted_shards = sorted(shards_data, key=lambda x: (x.get('index', ''), int(x.get('shard', 0))))
            
            # 统计信息 - 先遍历所有数据进行统计
            primary_count = 0
            replica_count = 0
            total_docs = 0
            state_counts = {}
            index_counts = {}
            
            for shard in shards_data:
                prirep = shard.get('prirep', '?')
                state = shard.get('state', 'UNKNOWN')
                docs = shard.get('docs', '0')
                
                # 统计
                if prirep == 'p':
                    primary_count += 1
                elif prirep == 'r':
                    replica_count += 1
                
                try:
                    total_docs += int(docs)
                except:
                    pass
                
                state_counts[state] = state_counts.get(state, 0) + 1
                
                # 提取索引服务名称用于统计
                index_name = shard.get('index', '')
                if 'logstash-loghub-' in index_name:
                    service_name = index_name.split('-')[3] if len(index_name.split('-')) > 3 else 'unknown'
                    index_counts[service_name] = index_counts.get(service_name, 0) + 1
            
            # 显示分片详情（限制数量）
            for i, shard in enumerate(sorted_shards):
                index_name = shard.get('index', 'N/A')
                shard_num = shard.get('shard', '0')
                prirep = shard.get('prirep', '?')
                state = shard.get('state', 'UNKNOWN')
                docs = shard.get('docs', '0')
                store = shard.get('store', '0')
                node = shard.get('node', 'N/A')
                
                # 截断长索引名称
                display_name = index_name[:50] if len(index_name) > 50 else index_name
                display_node = node[:15] if len(node) > 15 else node
                
                # 类型显示
                type_display = "主" if prirep == 'p' else "副" if prirep == 'r' else prirep
                
                # 状态颜色
                state_display = "正常" if state == "STARTED" else state
                
                print(f"{display_name:<50} {shard_num:<4} {type_display:<4} {state_display:<8} {docs:>10} {store:>8} {display_node:<15}")
                
                # 限制显示数量，避免输出过多
                if i >= 50:
                    remaining = len(sorted_shards) - 50
                    if remaining > 0:
                        print(f"... 还有 {remaining} 个分片")
                    break
            
            print("=" * 120)
            
            # 显示统计信息
            print(f"📊 分片统计:")
            print(f"   总分片数: {len(shards_data)}")
            print(f"   主分片: {primary_count}")
            print(f"   副本分片: {replica_count}")
            print(f"   总文档数: {total_docs:,}")
            
            print(f"\n🔍 分片状态:")
            for state, count in state_counts.items():
                emoji = "✅" if state == "STARTED" else "⚠️"
                print(f"   {emoji} {state}: {count}")
            
            # 显示TOP5服务的分片数
            if index_counts:
                top_services = sorted(index_counts.items(), key=lambda x: x[1], reverse=True)[:5]
                print(f"\n🏆 TOP5 服务分片数:")
                for service, count in top_services:
                    print(f"   {service}: {count}")
                    
        except Exception as e:
            print(f"❌ 查询分片信息失败: {e}")
    
    def get_system_stats(self):
        """获取系统资源统计信息"""
        print("=" * 60)
        print("🖥️  系统资源统计")
        print("=" * 60)
        
        try:
            # 获取节点统计信息
            nodes_stats = self.make_request("_nodes/stats/os,process,jvm,fs")
            if not nodes_stats:
                print("❌ 无法获取节点统计数据")
                return
            
            nodes_data = nodes_stats.get('nodes', {})
            if not nodes_data:
                print("❌ 节点数据为空")
                return
            
            print(f"找到 {len(nodes_data)} 个节点:")
            print("=" * 120)
            print(f"{'节点名称':<15} {'CPU%':<6} {'内存%':<6} {'堆内存%':<8} {'负载1m':<8} {'负载5m':<8} {'磁盘使用%':<10} {'磁盘可用':<12}")
            print("=" * 120)
            
            # 统计信息
            total_cpu = 0
            total_memory = 0
            total_heap = 0
            total_disk_used = 0
            total_disk_total = 0
            node_count = 0
            
            for node_id, node_data in nodes_data.items():
                node_name = node_data.get('name', 'unknown')
                
                # CPU 信息
                os_stats = node_data.get('os', {})
                cpu_percent = os_stats.get('cpu', {}).get('percent', 0)
                load_avg = os_stats.get('cpu', {}).get('load_average', {})
                load_1m = load_avg.get('1m', 0) if load_avg else 0
                load_5m = load_avg.get('5m', 0) if load_avg else 0
                
                # 内存信息
                mem_stats = os_stats.get('mem', {})
                mem_total = mem_stats.get('total_in_bytes', 0)
                mem_free = mem_stats.get('free_in_bytes', 0)
                mem_used_percent = ((mem_total - mem_free) / mem_total * 100) if mem_total > 0 else 0
                
                # JVM 堆内存
                jvm_stats = node_data.get('jvm', {})
                heap_stats = jvm_stats.get('mem', {})
                heap_used = heap_stats.get('heap_used_in_bytes', 0)
                heap_max = heap_stats.get('heap_max_in_bytes', 0)
                heap_percent = (heap_used / heap_max * 100) if heap_max > 0 else 0
                
                # 磁盘信息
                fs_stats = node_data.get('fs', {})
                fs_total = fs_stats.get('total', {})
                disk_total = fs_total.get('total_in_bytes', 0)
                disk_available = fs_total.get('available_in_bytes', 0)
                disk_used = disk_total - disk_available
                disk_used_percent = (disk_used / disk_total * 100) if disk_total > 0 else 0
                
                # 格式化显示
                disk_available_gb = disk_available / (1024**3)
                
                print(f"{node_name:<15} {cpu_percent:>5.1f} {mem_used_percent:>5.1f} {heap_percent:>7.1f} {load_1m:>7.2f} {load_5m:>7.2f} {disk_used_percent:>9.1f} {disk_available_gb:>10.1f}GB")
                
                # 累计统计
                total_cpu += cpu_percent
                total_memory += mem_used_percent
                total_heap += heap_percent
                total_disk_used += disk_used
                total_disk_total += disk_total
                node_count += 1
            
            print("=" * 120)
            
            # 显示平均值
            if node_count > 0:
                avg_cpu = total_cpu / node_count
                avg_memory = total_memory / node_count
                avg_heap = total_heap / node_count
                total_disk_used_percent = (total_disk_used / total_disk_total * 100) if total_disk_total > 0 else 0
                total_disk_available_gb = (total_disk_total - total_disk_used) / (1024**3)
                
                print(f"📊 平均统计:")
                print(f"   平均CPU使用率: {avg_cpu:.1f}%")
                print(f"   平均内存使用率: {avg_memory:.1f}%")
                print(f"   平均堆内存使用率: {avg_heap:.1f}%")
                print(f"   集群磁盘使用率: {total_disk_used_percent:.1f}%")
                print(f"   集群可用磁盘: {total_disk_available_gb:.1f} GB")
                
                # 资源告警
                print(f"\n🚨 资源告警:")
                if avg_cpu > 80:
                    print(f"   ⚠️  CPU使用率过高: {avg_cpu:.1f}%")
                elif avg_cpu > 60:
                    print(f"   ⚡ CPU使用率较高: {avg_cpu:.1f}%")
                else:
                    print(f"   ✅ CPU使用率正常: {avg_cpu:.1f}%")
                
                if avg_memory > 90:
                    print(f"   ⚠️  内存使用率过高: {avg_memory:.1f}%")
                elif avg_memory > 80:
                    print(f"   ⚡ 内存使用率较高: {avg_memory:.1f}%")
                else:
                    print(f"   ✅ 内存使用率正常: {avg_memory:.1f}%")
                
                if avg_heap > 85:
                    print(f"   ⚠️  堆内存使用率过高: {avg_heap:.1f}%")
                elif avg_heap > 75:
                    print(f"   ⚡ 堆内存使用率较高: {avg_heap:.1f}%")
                else:
                    print(f"   ✅ 堆内存使用率正常: {avg_heap:.1f}%")
                
                if total_disk_used_percent > 90:
                    print(f"   ⚠️  磁盘使用率过高: {total_disk_used_percent:.1f}%")
                elif total_disk_used_percent > 80:
                    print(f"   ⚡ 磁盘使用率较高: {total_disk_used_percent:.1f}%")
                else:
                    print(f"   ✅ 磁盘使用率正常: {total_disk_used_percent:.1f}%")
                    
        except Exception as e:
            print(f"❌ 获取系统统计失败: {e}")
    
    def search_logs(self, index_pattern: str, query: str = "*", size: int = 10):
        """搜索日志"""
        print("=" * 60)
        print("🔍 日志搜索")
        print("=" * 60)
        
        search_body = {
            "query": {
                "query_string": {
                    "query": query,
                    "default_field": "message"
                }
            },
            "sort": [
                {"@timestamp": {"order": "desc"}}
            ],
            "size": size
        }
        
        print(f"搜索索引: {index_pattern}")
        print(f"查询条件: {query}")
        print(f"返回数量: {size}")
        print("-" * 40)
        
        result = self.make_request(f"{index_pattern}/_search", "POST", search_body)
        if not result:
            return
        
        hits = result.get("hits", {}).get("hits", [])
        total = result.get("hits", {}).get("total", {})
        
        if isinstance(total, dict):
            total_count = total.get("value", 0)
        else:
            total_count = total
        
        print(f"总共找到 {total_count} 条记录，显示前 {len(hits)} 条:")
        print("=" * 80)
        
        for i, hit in enumerate(hits, 1):
            source = hit.get("_source", {})
            timestamp = source.get("@timestamp", "N/A")
            message = source.get("message", "N/A")
            level = source.get("level", source.get("log_level", "INFO"))
            
            print(f"{i}. [{timestamp}] [{level}]")
            print(f"   {message[:200]}{'...' if len(message) > 200 else ''}")
            print("-" * 80)
    
    def fuzzy_search_indices(self, keyword: str) -> List[str]:
        """模糊匹配索引名称"""
        indices = self.indices_cache.get("indices", [])
        matched = []
        
        keyword_lower = keyword.lower()
        for index in indices:
            if keyword_lower in index.lower():
                matched.append(index)
        
        return matched[:10]  # 返回前10个匹配结果
    
    def show_menu(self):
        """显示主菜单"""
        print("\n" + "=" * 60)
        print("🚀 Elasticsearch 管理工具")
        print("=" * 60)
        print("1. 集群健康状态检查")
        print("2. 索引信息查询 (按大小排序)")
        print("3. 分片信息查询 (支持日期)")
        print("4. 系统资源统计 (CPU/内存/磁盘)")
        print("0. 退出")
        print("-" * 60)
    
    def interactive_mode(self):
        """交互模式"""
        print("🎯 ES 管理工具启动成功!")
        print(f"连接地址: {self.es_url}")
        
        while True:
            self.show_menu()
            try:
                choice = input("请选择功能 [0-4]: ").strip()
                
                if choice == "0":
                    print("👋 再见!")
                    break
                elif choice == "1":
                    self.check_cluster_health()
                elif choice == "2":
                    date_input = input(f"输入日期 (默认今天 {datetime.now().strftime('%Y-%m-%d')}): ").strip()
                    if date_input:
                        pattern = f"*{date_input}*"
                    else:
                        pattern = None  # 使用默认的今天
                    self.get_indices_info(pattern)
                elif choice == "3":
                    date_input = input(f"输入日期 (默认今天 {datetime.now().strftime('%Y-%m-%d')}): ").strip()
                    if not date_input:
                        date_input = None
                    self.get_shards_info(date_input)
                elif choice == "4":
                    self.get_system_stats()
                else:
                    print("❌ 无效选择，请重新输入")
                
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
    
    manager = ESManager(es_url)
    
    try:
        # 测试连接
        health = manager.make_request("_cluster/health")
        if not health:
            print(f"❌ 无法连接到 Elasticsearch: {es_url}")
            return
        
        manager.interactive_mode()
    except Exception as e:
        print(f"❌ 启动失败: {e}")

if __name__ == "__main__":
    main()