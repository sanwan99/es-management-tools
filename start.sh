#!/bin/bash
# ES 管理工具启动脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Elasticsearch 管理工具${NC}"
echo -e "${BLUE}============================${NC}"

# 检查 Python 环境
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python3 未安装${NC}"
    exit 1
fi

# 检查依赖
if [ ! -f "requirements.txt" ]; then
    echo -e "${YELLOW}⚠️  创建 requirements.txt...${NC}"
    cat > requirements.txt << EOF
requests>=2.25.0
EOF
fi

# 安装依赖
echo -e "${YELLOW}📦 检查依赖...${NC}"
pip3 install -r requirements.txt --quiet

# 检查脚本文件
if [ ! -f "es_manager.py" ]; then
    echo -e "${RED}❌ es_manager.py 文件不存在${NC}"
    exit 1
fi

# 设置可执行权限
chmod +x es_manager.py

# 显示菜单
show_menu() {
    echo -e "${BLUE}请选择操作模式:${NC}"
    echo -e "${YELLOW}1.${NC} 完整ES管理工具"
    echo -e "${YELLOW}2.${NC} 索引监控记录工具"
    echo -e "${YELLOW}3.${NC} 环境快速查询"
    echo -e "${YELLOW}4.${NC} SMS验证码查询"
    echo -e "${YELLOW}0.${NC} 退出"
    echo ""
}

# 环境快速查询
env_query() {
    echo -e "${BLUE}🔍 环境快速查询${NC}"
    echo -e "${BLUE}================${NC}"
    echo -e "${YELLOW}常用环境关键词:${NC}"
    echo -e "  ${GREEN}prd${NC}  - 生产环境 (*-prd-*)"
    echo -e "  ${GREEN}dev${NC}  - 开发环境 (*-dev-*)"
    echo -e "  ${GREEN}test${NC} - 测试环境 (*-test-*)"
    echo -e "  ${GREEN}int${NC}  - 集成环境 (*-int-*)"
    echo -e "  ${GREEN}staging${NC} - 预发环境 (*-staging-*)"
    echo ""
    
    while true; do
        read -p "请输入环境关键词 (或输入 'q' 退出): " env_keyword
        
        if [ "$env_keyword" = "q" ]; then
            break
        fi
        
        if [ -z "$env_keyword" ]; then
            echo -e "${RED}❌ 环境关键词不能为空${NC}"
            continue
        fi
        
        # 构造查询模式
        pattern="*-${env_keyword}-*"
        echo -e "${YELLOW}🔍 查询模式: ${pattern}${NC}"
        echo -e "${YELLOW}📊 正在查询索引信息...${NC}"
        
        # 创建临时Python脚本进行查询
        cat > /tmp/env_query.py << 'EOF'
import sys
import requests
from datetime import datetime

def make_request(es_url, endpoint):
    url = f"{es_url}/{endpoint}"
    try:
        response = requests.get(url, timeout=30)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"❌ 请求失败: {e}")
        return None

def convert_size_to_gb(size_str):
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

def query_env_indices(es_url, pattern):
    # 查询索引信息
    indices_data = make_request(es_url, f"_cat/indices/{pattern}?format=json&h=index,pri,rep,docs.count,store.size&s=store.size:desc")
    if not indices_data:
        print("❌ 无法获取索引数据")
        return
    
    if not indices_data:
        print(f"❌ 未找到匹配 {pattern} 的索引")
        return
    
    print(f"✅ 找到 {len(indices_data)} 个索引:")
    print("=" * 90)
    print(f"{'序号':<4} {'索引名称':<50} {'大小(GB)':<10} {'分片数':<8} {'文档数':<12}")
    print("=" * 90)
    
    total_size = 0
    total_docs = 0
    total_shards = 0
    
    for i, idx in enumerate(indices_data[:20], 1):
        index_name = idx.get('index', 'N/A')
        size_str = idx.get('store.size', '0')
        size_gb = convert_size_to_gb(size_str)
        primary_shards = int(idx.get('pri', 0))
        replica_shards = int(idx.get('rep', 0))
        shards = primary_shards + replica_shards
        docs_count = int(idx.get('docs.count', 0))
        
        # 截断过长的索引名称
        display_name = index_name[:50] if len(index_name) > 50 else index_name
        
        print(f"{i:<4} {display_name:<50} {size_gb:>8.2f}  {shards:>6}   {docs_count:>10,}")
        
        total_size += size_gb
        total_docs += docs_count
        total_shards += shards
    
    if len(indices_data) > 20:
        remaining = len(indices_data) - 20
        print(f"... 还有 {remaining} 个索引")
    
    print("=" * 90)
    print(f"📊 总计: {len(indices_data)} 个索引, {total_size:.2f} GB, {total_shards} 个分片, {total_docs:,} 个文档")
    
    # 查询分片信息
    print(f"\n🔧 分片统计:")
    shards_data = make_request(es_url, f"_cat/shards/{pattern}?format=json&h=index,shard,prirep,state")
    if shards_data:
        primary_count = len([s for s in shards_data if s.get('prirep') == 'p'])
        replica_count = len([s for s in shards_data if s.get('prirep') == 'r'])
        
        # 分片状态统计
        states = {}
        for shard in shards_data:
            state = shard.get('state', 'unknown')
            states[state] = states.get(state, 0) + 1
        
        print(f"   总分片数: {len(shards_data)}")
        print(f"   主分片: {primary_count}")
        print(f"   副本分片: {replica_count}")
        
        print(f"   分片状态:")
        for state, count in states.items():
            emoji = "✅" if state == "STARTED" else "⚠️"
            print(f"     {emoji} {state}: {count}")

if __name__ == "__main__":
    es_url = sys.argv[1] if len(sys.argv) > 1 else "http://192.168.0.93:9201"
    pattern = sys.argv[2] if len(sys.argv) > 2 else "*"
    query_env_indices(es_url, pattern)
EOF
        
        # 执行查询
        python3 /tmp/env_query.py "http://192.168.0.93:9201" "$pattern"
        
        # 清理临时文件
        rm -f /tmp/env_query.py
        
        echo ""
        echo -e "${BLUE}按回车键继续...${NC}"
        read
    done
}

# 启动程序
echo -e "${GREEN}✅ 环境检查完成${NC}"
echo ""

# 如果有命令行参数，直接传递给 es_manager.py
if [ $# -gt 0 ]; then
    echo -e "${GREEN}✅ 启动 ES 管理工具...${NC}"
    python3 es_manager.py "$@"
    exit 0
fi

# 交互模式
while true; do
    show_menu
    read -p "请选择 [0-4]: " choice
    
    case $choice in
        1)
            echo -e "${GREEN}✅ 启动完整ES管理工具...${NC}"
            python3 es_manager.py
            ;;
        2)
            echo -e "${GREEN}✅ 启动索引监控记录工具...${NC}"
            python3 es_index_logger.py
            ;;
        3)
            env_query
            ;;
        4)
            echo -e "${GREEN}✅ 启动SMS验证码查询工具...${NC}"
            if [ -f "sms_query.py" ]; then
                python3 sms_query.py
            elif [ -f "sms_quick" ]; then
                ./sms_quick
            else
                echo -e "${RED}❌ SMS查询工具不存在${NC}"
            fi
            ;;
        0)
            echo -e "${GREEN}👋 再见!${NC}"
            break
            ;;
        *)
            echo -e "${RED}❌ 无效选择，请重新输入${NC}"
            ;;
    esac
    
    if [ "$choice" != "0" ]; then
        echo ""
        echo -e "${BLUE}按回车键继续...${NC}"
        read
    fi
done