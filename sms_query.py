#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
手机号验证码查询工具
通过手机号查询过去15分钟内的验证码短信
"""

import requests
import json
import re
from datetime import datetime, timedelta
import datetime as dt
from typing import List, Dict, Any

class SMSQuery:
    def __init__(self, es_url: str = "http://192.168.0.93:9201"):
        self.es_url = es_url.rstrip('/')
    
    def clean_phone_number(self, phone: str) -> str:
        """清理手机号：去除空格、换行、制表符等空白字符"""
        if not phone:
            return ""
        # 去除所有空白字符（空格、制表符、换行符等）
        cleaned = re.sub(r'\s+', '', phone.strip())
        # 去除常见的分隔符
        cleaned = cleaned.replace('-', '').replace('(', '').replace(')', '').replace('+86', '')
        return cleaned
    
    def validate_phone_number(self, phone: str) -> bool:
        """验证手机号格式"""
        # 先清理手机号
        cleaned_phone = self.clean_phone_number(phone)
        # 中国手机号正则：11位数字，以1开头
        pattern = r'^1[3-9]\d{9}$'
        return bool(re.match(pattern, cleaned_phone))
    
    def get_time_range(self, minutes: int = 15) -> tuple:
        """获取时间范围 (过去N分钟到现在)"""
        now = datetime.now(dt.timezone.utc) if hasattr(dt, 'timezone') else datetime.utcnow()
        start_time = now - timedelta(minutes=minutes)
        
        # 转换为ES需要的ISO格式
        end_time_str = now.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
        start_time_str = start_time.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
        
        return start_time_str, end_time_str
    
    def search_sms_codes(self, phone: str) -> List[Dict[str, Any]]:
        """搜索验证码短信"""
        # 清理手机号
        cleaned_phone = self.clean_phone_number(phone)
        
        if not self.validate_phone_number(phone):
            print(f"❌ 手机号格式不正确: {phone}")
            if phone != cleaned_phone:
                print(f"💡 清理后的手机号: {cleaned_phone}")
            print(f"💡 请输入11位中国手机号，如: 13812345678")
            return []
        
        # 显示原始输入和清理后的手机号（如果不同）
        if phone != cleaned_phone:
            print(f"🔍 原始输入: {repr(phone)}")
            print(f"🔍 清理后查询: {cleaned_phone}")
        else:
            print(f"🔍 查询手机号: {cleaned_phone}")
            
        print(f"📱 查询范围: 过去15分钟内的验证码短信")
        
        # 获取时间范围
        start_time, end_time = self.get_time_range(15)
        print(f"⏰ 时间范围: {start_time} ~ {end_time}")
        
        # 构建查询 - 尝试多个可能的时间字段
        query = {
            "query": {
                "bool": {
                    "must": [
                        {
                            "bool": {
                                "should": [
                                    {
                                        "range": {
                                            "@timestamp": {
                                                "from": start_time,
                                                "to": end_time,
                                                "include_lower": True,
                                                "include_upper": True
                                            }
                                        }
                                    },
                                    {
                                        "range": {
                                            "time": {
                                                "from": start_time,
                                                "to": end_time,
                                                "include_lower": True,
                                                "include_upper": True
                                            }
                                        }
                                    },
                                    {
                                        "range": {
                                            "timestamp": {
                                                "from": start_time,
                                                "to": end_time,
                                                "include_lower": True,
                                                "include_upper": True
                                            }
                                        }
                                    }
                                ],
                                "minimum_should_match": 1
                            }
                        },
                        {
                            "query_string": {
                                "query": f"{cleaned_phone} AND 验证码",
                                "default_operator": "and"
                            }
                        }
                    ]
                }
            },
            # 先不排序，避免字段不存在的问题
            "size": 20
        }
        
        try:
            # 发送搜索请求
            url = f"{self.es_url}/*message-center*/_search"
            headers = {'Content-Type': 'application/json'}
            
            print(f"🌐 请求地址: {url}")
            
            response = requests.post(url, 
                                   headers=headers, 
                                   data=json.dumps(query), 
                                   timeout=30)
            
            print(f"📊 响应状态: {response.status_code}")
            
            if response.status_code == 200:
                result = response.json()
                hits = result.get('hits', {}).get('hits', [])
                total = result.get('hits', {}).get('total', {})
                
                if isinstance(total, dict):
                    total_count = total.get('value', 0)
                else:
                    total_count = total
                
                print(f"✅ 查询成功! 找到 {total_count} 条相关记录")
                return hits
            else:
                print(f"❌ 查询失败: {response.status_code}")
                print(f"错误信息: {response.text}")
                return []
                
        except Exception as e:
            print(f"❌ 请求异常: {e}")
            return []
    
    def extract_verification_code(self, message: str) -> str:
        """从短信内容中提取验证码"""
        if not message:
            return "未找到"
        
        # 常见验证码模式
        patterns = [
            r'验证码[：:是为]\s*(\d{4,8})',
            r'验证码是[：:]\s*(\d{4,8})',
            r'验证码为[：:]\s*(\d{4,8})',
            r'动态密码[：:]\s*(\d{4,8})',
            r'短信验证码[：:]\s*(\d{4,8})',
            r'(\d{4,8})\s*为您的验证码',
            r'您的验证码是\s*(\d{4,8})',
            r'验证码\s*(\d{4,8})',
            r'code[：:]\s*(\d{4,8})',
            r'验证码.*?(\d{4,8})',  # 更宽泛的匹配
        ]
        
        for pattern in patterns:
            match = re.search(pattern, message, re.IGNORECASE)
            if match:
                return match.group(1)
        
        # 如果没有匹配到，查找所有4-8位数字
        numbers = re.findall(r'\b\d{4,8}\b', message)
        if numbers:
            return numbers[0]
        
        return "未识别"
    
    def display_results(self, hits: List[Dict[str, Any]]):
        """显示查询结果"""
        if not hits:
            print("\n❌ 未找到相关验证码短信")
            return
        
        print(f"\n📋 查询结果 (共 {len(hits)} 条):")
        print("=" * 120)
        print(f"{'序号':<4} {'时间':<20} {'验证码':<10} {'短信内容':<70}")
        print("=" * 120)
        
        for i, hit in enumerate(hits, 1):
            source = hit.get('_source', {})
            
            # 提取关键信息 - 适配实际ES数据结构
            timestamp = source.get('time', source.get('@timestamp', source.get('timestamp', 'N/A')))
            # 优先从msgObj中获取内容，然后尝试message字段
            message_content = 'N/A'
            receiver = 'N/A'
            msg_obj = source.get('msgObj', {})
            
            if isinstance(msg_obj, dict) and 'object' in msg_obj:
                obj = msg_obj['object']
                if isinstance(obj, dict) and 'requestBody' in obj:
                    try:
                        # 解析requestBody中的JSON
                        request_body = json.loads(obj['requestBody'])
                        message_content = request_body.get('content', 'N/A')
                        receiver = request_body.get('receiver', 'N/A')
                    except (json.JSONDecodeError, TypeError):
                        pass
            
            # 如果没有找到，尝试其他字段
            if message_content == 'N/A':
                message_content = source.get('message', 'N/A')
            
            # 调试信息：显示实际的字段（可选）
            # if i == 1:  # 只在第一条记录时显示
            #     print(f"# 调试信息 - ES数据字段: {list(source.keys())}")
            #     print(f"# 调试信息 - msgObj内容: {source.get('msgObj', 'N/A')}")
            #     print(f"# 调试信息 - message内容: {source.get('message', 'N/A')}")
            
            # 格式化时间
            if timestamp != 'N/A':
                try:
                    if isinstance(timestamp, str) and 'T' in timestamp:
                        dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                        # 转换为本地时间显示
                        local_dt = dt + timedelta(hours=8)  # UTC+8
                        time_str = local_dt.strftime('%m-%d %H:%M:%S')
                    elif isinstance(timestamp, (int, float)):
                        # 时间戳格式
                        if timestamp > 1000000000000:  # 毫秒时间戳
                            timestamp = timestamp / 1000
                        dt = datetime.fromtimestamp(timestamp)
                        time_str = dt.strftime('%m-%d %H:%M:%S')
                    else:
                        time_str = str(timestamp)[:19] if len(str(timestamp)) > 19 else str(timestamp)
                except Exception as e:
                    time_str = str(timestamp)[:19] if len(str(timestamp)) > 19 else str(timestamp)
            else:
                time_str = 'N/A'
            
            # 提取验证码
            if message_content and message_content != 'N/A':
                code = self.extract_verification_code(message_content)
            else:
                code = "未找到"
            
            # 截断过长的短信内容
            if message_content and message_content != 'N/A':
                display_message = message_content[:70] if len(message_content) > 70 else message_content
                display_message = display_message.replace('\n', ' ').replace('\r', ' ')
            else:
                display_message = "无内容"
            
            print(f"{i:<4} {time_str:<20} {code:<10} {display_message:<70}")
        
        print("=" * 120)
    
    def interactive_query(self):
        """交互式查询"""
        print("📱 手机号验证码查询工具")
        print("=" * 50)
        print("💡 提示: 支持自动清理空格、分隔符等格式")
        print("   如: ' 138 1234 5678 ' 或 '+86-138-1234-5678'")
        
        while True:
            try:
                phone = input("\n请输入手机号 (输入 'q' 退出): ").strip()
                
                if phone.lower() == 'q':
                    print("👋 再见!")
                    break
                
                if not phone:
                    print("❌ 请输入手机号")
                    continue
                
                # 清理手机号并验证
                cleaned_phone = self.clean_phone_number(phone)
                if not self.validate_phone_number(phone):
                    print("❌ 手机号格式不正确，请输入11位数字的中国手机号")
                    if phone != cleaned_phone and cleaned_phone:
                        print(f"💡 清理后的手机号: {cleaned_phone}")
                        print("💡 如果这是正确的手机号，请直接输入清理后的版本")
                    continue
                
                # 执行查询
                hits = self.search_sms_codes(phone)
                self.display_results(hits)
                
            except KeyboardInterrupt:
                print("\n👋 再见!")
                break
            except Exception as e:
                print(f"❌ 发生错误: {e}")

def main():
    """主函数"""
    import sys
    
    if len(sys.argv) > 1:
        # 命令行模式
        phone = sys.argv[1]
        sms_query = SMSQuery()
        hits = sms_query.search_sms_codes(phone)
        sms_query.display_results(hits)
    else:
        # 交互模式
        sms_query = SMSQuery()
        sms_query.interactive_query()

if __name__ == "__main__":
    main()