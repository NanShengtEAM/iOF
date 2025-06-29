#!/bin/bash
#     _    ____     ______          ___      ____     __  
#    (_)  / __ \   / ____/         <  /     / __ \   / /_ 
#   / /  / / / /  / /_             / /     / / / /  / __ \
#  / /  / /_/ /  / __/            / /   _ / /_/ /  / /_/ /
# /_/   \____/  /_/              /_/   (_)\____/  /_.___/ 
#本项目采用MIT许可证，但请保证不用于盈利/商业目的。
#iOF致力于管理本地OpenFrp客户端，加快安装速度，优化方案体现。
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_dependency() {
    local tool=$1
    local package=${2:-$tool}
    
    if ! command -v "$tool" &> /dev/null; then
        echo -e "${YELLOW}[iOF]警告: 未找到 $tool，尝试安装...${NC}"
        
        if command -v apt-get &> /dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y -qq "$package"
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y -q "$package"
        elif command -v yum &> /dev/null; then
            sudo yum install -y -q "$package"
        elif command -v zypper &> /dev/null; then
            sudo zypper -n install -q "$package"
        elif command -v pacman &> /dev/null; then
            sudo pacman -Syu --noconfirm --quiet "$package"
        elif command -v apk &> /dev/null; then
            sudo apk add --quiet "$package"
        else
            echo -e "${RED}[iOF]错误: 无法自动安装 $tool，请手动安装 $package${NC}"
            exit 1
        fi
        
        command -v "$tool" &> /dev/null || {
            echo -e "${RED}[iOF]错误: $tool 安装失败，请手动安装 $package${NC}"
            exit 1
        }
        echo "[iOF]$tool 已安装"
    fi
}

fetch_json_data() {
    echo "[iOF]获取软件信息..."
    json_data=$(curl -s "https://api.openfrp.net/commonQuery/get?key=software")
    jq -e '.flag' <<< "$json_data" >/dev/null || {
        echo -e "${RED}[iOF]错误: 无法获取软件信息${NC}"
        exit 1
    }
}

detect_architecture() {
    case $(uname -m) in
        x86_64)    echo "amd64" ;;
        aarch64)   echo "arm64" ;;
        armv7l)    echo "arm" ;;
        i686|i386) echo "386" ;;
        mips)      echo "mips" ;;
        *)         echo "unknown" ;;
    esac
}

extract_linux_options() {
    linux_index=$(jq -r '.data.soft | map(.os) | index("linux")' <<< "$json_data")
    [[ "$linux_index" == "null" ]] && {
        echo -e "${RED}[iOF]错误: API响应异常${NC}"
        exit 1
    }
    
    arch_count=$(jq -r ".data.soft[$linux_index].arch | length" <<< "$json_data")
    for ((i=0; i<arch_count; i++)); do
        arch_options+=("$(jq -r ".data.soft[$linux_index].arch[$i].label" <<< "$json_data")")
        arch_files+=("$(jq -r ".data.soft[$linux_index].arch[$i].file" <<< "$json_data")")
        arch_details+=("$(jq -r ".data.soft[$linux_index].arch[$i].details" <<< "$json_data" | 
            sed -e 's/<[^>]*>//g' -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&amp;/\&/g')")
    done
}

select_architecture() {
    detected_arch=$(detect_architecture)
    echo "[iOF]系统架构: $(uname -m) 建议架构: $detected_arch"
    echo "选择Openfrp启动器架构:"
    
    for idx in "${!arch_options[@]}"; do
        [[ "${arch_options[$idx]}" == *"$detected_arch"* ]] && 
            echo "  [$((idx+1))] ${arch_options[$idx]} (推荐)" ||
            echo "  [$((idx+1))] ${arch_options[$idx]}"
    done
    echo "  [0] 退出"
    
    read -p "输入选择: " choice
    [[ "$choice" == "0" ]] && { echo "[iOF]退出"; exit 0; }
    
    [[ $choice -lt 1 || $choice -gt ${#arch_options[@]} ]] && {
        echo -e "${RED}[iOF]错误: 无效选择${NC}"; exit 1;
    }
    
    arch_index=$((choice-1))
}

download_and_install() {
    file_url="${arch_files[$arch_index]}"
    [[ -z "$file_url" || "$file_url" == "null" ]] && {
        echo -e "${RED}[iOF]错误: 此架构无可用下载${NC}"; exit 1;
    }

    echo "选择下载源:"
    echo "  [1] $source1_label"
    echo "  [2] $source2_label"
    read -p "输入选项: " source_choice
    
    if [[ "$source_choice" == "1" ]]; then
        base_url="$source1_value"
    elif [[ "$source_choice" == "2" ]]; then
        base_url="$source2_value"
    else
        echo -e "${YELLOW}[iOF]使用默认下载源${NC}"
        base_url="$source1_value"
    fi

    [[ "$file_url" == http* ]] && full_url="$file_url" || 
        full_url="${base_url}${latest}${file_url}"

    default_dir="$HOME/iopenfrp"
    echo "[iOF]安装目录 (默认: $default_dir):"
    read -p "[iOF]请输入路径: " install_dir
    install_dir=${install_dir:-$default_dir}
    
    arch_dir="$install_dir/${arch_options[$arch_index]//\//_}_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$arch_dir" || { echo -e "${RED}[iOF]无法创建目录${NC}"; exit 1; }
    cd "$arch_dir" || exit 1
    
    filename=$(basename "$full_url")
    echo "[iOF]下载: $filename"
    wget -q --show-progress -O "$filename" "$full_url" || {
        echo -e "${RED}下载失败${NC}"; exit 1;
    }
    
    process_downloaded_file
}

process_downloaded_file() {
    case "$filename" in
        *.AppImage)
            chmod +x "$filename"
            echo "运行命令:"
            echo "  cd \"$arch_dir\" && ./$filename"
            ;;
        *.tar.gz)
            tar -xzf "$filename"
            executable=$(find . -name 'frpc*' -executable -type f | head -1)
            [[ -n "$executable" ]] && {
            } || echo -e "${YELLOW}未找到可执行文件${NC}"
            ;;
        *.zip)
            unzip -q "$filename"
            executable=$(find . -name 'frpc*' -executable -type f | head -1)
            [[ -n "$executable" ]] && {
                chmod +x "$executable"
                echo "运行命令:"
                echo "  cd \"$arch_dir\" && ./$executable"
            } || echo -e "${YELLOW}未找到可执行文件${NC}"
            ;;
        *)
            file "$filename" | grep -q "executable" && {
                chmod +x "$filename"
                echo "运行命令:"
                echo "  cd \"$arch_dir\" && ./$filename"
            } || echo -e "${YELLOW}未识别可执行文件${NC}"
            ;;
    esac
    echo "文件路径: $arch_dir"
}

# 主程序流程
check_dependency "curl"
check_dependency "jq"
check_dependency "wget"
check_dependency "tar"
check_dependency "unzip"

fetch_json_data

source1_label=$(jq -r '.data.source[0].label' <<< "$json_data")
source1_value=$(jq -r '.data.source[0].value' <<< "$json_data")
source2_label=$(jq -r '.data.source[1].label' <<< "$json_data")
source2_value=$(jq -r '.data.source[1].value' <<< "$json_data")

echo "========================================"
echo " iOpenFrp For Linux (iOF) "
echo " Version: 1.0b "
echo "========================================"

arch_options=()
arch_files=()
arch_details=()
extract_linux_options
select_architecture
download_and_install

echo "[iOF]安装(下载)完成"