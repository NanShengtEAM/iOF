#!/bin/bash
#     _    ____     ______          ___      ____     __  
#    (_)  / __ \   / ____/         <  /     / __ \   / /_ 
#   / /  / / / /  / /_             / /     / / / /  / __ \
#  / /  / /_/ /  / __/            / /   _ / /_/ /  / /_/ /
# /_/   \____/  /_/              /_/   (_)\____/  /_.___/ 
#本项目采用MIT许可证，但请保证不用于盈利/商业目的。
#iOF致力于管理本地OpenFrp客户端，加快安装速度，优化方案体现。

# 优化的颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
NC='\033[0m' # 无颜色

# 新增：模式选择变量
DOWNLOAD_MODE=""

# 新增：显示欢迎界面和模式选择
show_welcome_and_select_mode() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${WHITE}${BOLD} iOpenFrp For Linux (iOF) ${NC}"
    echo -e "${WHITE}${BOLD} Version: 1.0b ${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo -e "${GREEN}${BOLD}请选择下载模式:${NC}"
    echo -e "${BLUE}  [1] 自动下载模式 ${GREEN}(推荐)${NC} - 自动检测架构并下载"
    echo -e "${BLUE}  [2] 手动下载模式${NC} - 手动选择所有选项"
    echo -e "${RED}  [0] 退出程序${NC}"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    while true; do
        read -p "$(echo -e "${WHITE}请输入您的选择 [0-2]: ${NC}")" choice
        case $choice in
            1)
                DOWNLOAD_MODE="auto"
                echo -e "${GREEN}✓ 已选择自动下载模式${NC}"
                break
                ;;
            2)
                DOWNLOAD_MODE="manual"
                echo -e "${GREEN}✓ 已选择手动下载模式${NC}"
                break
                ;;
            0)
                echo -e "${YELLOW}感谢使用 iOF，再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}✗ 无效选择，请输入 0、1 或 2${NC}"
                ;;
        esac
    done
    echo ""
}

check_dependency() {
    local tool=$1
    local package=${2:-$tool}
    
    if ! command -v "$tool" &> /dev/null; then
        echo -e "${YELLOW}${BOLD}[iOF]${NC} ${YELLOW}警告: 未找到 $tool，尝试安装...${NC}"
        
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
            echo -e "${RED}${BOLD}[iOF]${NC} ${RED}错误: 无法自动安装 $tool，请手动安装 $package${NC}"
            exit 1
        fi
        
        command -v "$tool" &> /dev/null || {
            echo -e "${RED}${BOLD}[iOF]${NC} ${RED}错误: $tool 安装失败，请手动安装 $package${NC}"
            exit 1
        }
        echo -e "${GREEN}${BOLD}[iOF]${NC} ${GREEN}✓ $tool 已安装${NC}"
    fi
}

fetch_json_data() {
    echo -e "${BLUE}${BOLD}[iOF]${NC} ${BLUE}正在获取软件信息...${NC}"
    json_data=$(curl -s "https://api.openfrp.net/commonQuery/get?key=software")
    jq -e '.flag' <<< "$json_data" >/dev/null || {
        echo -e "${RED}${BOLD}[iOF]${NC} ${RED}错误: 无法获取软件信息${NC}"
        exit 1
    }
    echo -e "${GREEN}${BOLD}[iOF]${NC} ${GREEN}✓ 软件信息获取成功${NC}"
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
        echo -e "${RED}${BOLD}[iOF]${NC} ${RED}错误: API响应异常${NC}"
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

# 修改：根据模式选择架构
select_architecture() {
    detected_arch=$(detect_architecture)
    echo -e "${CYAN}${BOLD}[iOF]${NC} ${CYAN}系统架构: ${WHITE}$(uname -m)${NC} ${CYAN}建议架构: ${GREEN}$detected_arch${NC}"
    
    if [[ "$DOWNLOAD_MODE" == "auto" ]]; then
        # 自动模式：自动选择推荐架构
        for idx in "${!arch_options[@]}"; do
            if [[ "${arch_options[$idx]}" == *"$detected_arch"* ]]; then
                arch_index=$idx
                echo -e "${GREEN}${BOLD}[iOF]${NC} ${GREEN}自动选择推荐架构: ${WHITE}${arch_options[$arch_index]}${NC}"
                return
            fi
        done
        # 如果没找到推荐的，使用第一个
        arch_index=0
        echo -e "${YELLOW}${BOLD}[iOF]${NC} ${YELLOW}未找到推荐架构，使用: ${WHITE}${arch_options[$arch_index]}${NC}"
    else
        # 手动模式：让用户选择
        echo -e "${BLUE}${BOLD}请选择Openfrp启动器架构:${NC}"
        
        for idx in "${!arch_options[@]}"; do
            if [[ "${arch_options[$idx]}" == *"$detected_arch"* ]]; then
                echo -e "${GREEN}  [$((idx+1))] ${arch_options[$idx]} ${BOLD}(推荐)${NC}"
            else
                echo -e "${WHITE}  [$((idx+1))] ${arch_options[$idx]}${NC}"
            fi
        done
        echo -e "${RED}  [0] 退出${NC}"
        
        while true; do
            read -p "$(echo -e "${WHITE}输入选择: ${NC}")" choice
            [[ "$choice" == "0" ]] && { echo -e "${YELLOW}[iOF]退出${NC}"; exit 0; }
            
            if [[ $choice -ge 1 && $choice -le ${#arch_options[@]} ]]; then
                arch_index=$((choice-1))
                echo -e "${GREEN}✓ 已选择: ${WHITE}${arch_options[$arch_index]}${NC}"
                break
            else
                echo -e "${RED}✗ 无效选择，请输入 0 到 ${#arch_options[@]} 之间的数字${NC}"
            fi
        done
    fi
}

# 修改：根据模式处理下载
download_and_install() {
    file_url="${arch_files[$arch_index]}"
    [[ -z "$file_url" || "$file_url" == "null" ]] && {
        echo -e "${RED}${BOLD}[iOF]${NC} ${RED}错误: 此架构无可用下载${NC}"; exit 1;
    }

    if [[ "$DOWNLOAD_MODE" == "auto" ]]; then
        # 自动模式：使用默认下载源
        base_url="$source1_value"
        echo -e "${GREEN}${BOLD}[iOF]${NC} ${GREEN}自动选择下载源: ${WHITE}$source1_label${NC}"
    else
        # 手动模式：让用户选择下载源
        echo -e "${BLUE}${BOLD}请选择下载源:${NC}"
        echo -e "${WHITE}  [1] $source1_label${NC}"
        echo -e "${WHITE}  [2] $source2_label${NC}"
        
        while true; do
            read -p "$(echo -e "${WHITE}输入选项 [1-2]: ${NC}")" source_choice
            
            if [[ "$source_choice" == "1" ]]; then
                base_url="$source1_value"
                echo -e "${GREEN}✓ 已选择: ${WHITE}$source1_label${NC}"
                break
            elif [[ "$source_choice" == "2" ]]; then
                base_url="$source2_value"
                echo -e "${GREEN}✓ 已选择: ${WHITE}$source2_label${NC}"
                break
            else
                echo -e "${RED}✗ 无效选择，请输入 1 或 2${NC}"
            fi
        done
    fi

    [[ "$file_url" == http* ]] && full_url="$file_url" || 
        full_url="${base_url}${latest}${file_url}"

    default_dir="$HOME/iopenfrp"
    
    if [[ "$DOWNLOAD_MODE" == "auto" ]]; then
        # 自动模式：使用默认目录
        install_dir="$default_dir"
        echo -e "${GREEN}${BOLD}[iOF]${NC} ${GREEN}自动选择安装目录: ${WHITE}$install_dir${NC}"
    else
        # 手动模式：让用户选择目录
        echo -e "${BLUE}${BOLD}[iOF]${NC} ${BLUE}安装目录 (默认: ${WHITE}$default_dir${BLUE}):${NC}"
        read -p "$(echo -e "${WHITE}请输入路径 (直接回车使用默认): ${NC}")" install_dir
        install_dir=${install_dir:-$default_dir}
        echo -e "${GREEN}✓ 安装目录: ${WHITE}$install_dir${NC}"
    fi
    
    arch_dir="$install_dir/${arch_options[$arch_index]//\//_}_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$arch_dir" || { echo -e "${RED}${BOLD}[iOF]${NC} ${RED}无法创建目录${NC}"; exit 1; }
    cd "$arch_dir" || exit 1
    
    filename=$(basename "$full_url")
    echo -e "${PURPLE}${BOLD}[iOF]${NC} ${PURPLE}开始下载: ${WHITE}$filename${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    wget -q --show-progress -O "$filename" "$full_url" || {
        echo -e "${RED}${BOLD}下载失败${NC}"; exit 1;
    }
    
    echo -e "${GREEN}${BOLD}✓ 下载完成${NC}"
    process_downloaded_file
}

process_downloaded_file() {
    echo -e "${BLUE}${BOLD}[iOF]${NC} ${BLUE}正在处理下载的文件...${NC}"
    
    case "$filename" in
        *.AppImage)
            chmod +x "$filename"
            echo -e "${GREEN}${BOLD}运行命令:${NC}"
            echo -e "${WHITE}  cd \"$arch_dir\" && ./$filename${NC}"
            ;;
        *.tar.gz)
            tar -xzf "$filename"
            executable=$(find . -name 'frpc*' -executable -type f | head -1)
            [[ -n "$executable" ]] && {
                chmod +x "$executable"
                echo -e "${GREEN}${BOLD}运行命令:${NC}"
                echo -e "${WHITE}  cd \"$arch_dir\" && ./$executable${NC}"
            } || echo -e "${YELLOW}${BOLD}[iOF]${NC} ${YELLOW}未找到可执行文件${NC}"
            ;;
        *.zip)
            unzip -q "$filename"
            executable=$(find . -name 'frpc*' -executable -type f | head -1)
            [[ -n "$executable" ]] && {
                chmod +x "$executable"
                echo -e "${GREEN}${BOLD}运行命令:${NC}"
                echo -e "${WHITE}  cd \"$arch_dir\" && ./$executable${NC}"
            } || echo -e "${YELLOW}${BOLD}[iOF]${NC} ${YELLOW}未找到可执行文件${NC}"
            ;;
        *)
            file "$filename" | grep -q "executable" && {
                chmod +x "$filename"
                echo -e "${GREEN}${BOLD}运行命令:${NC}"
                echo -e "${WHITE}  cd \"$arch_dir\" && ./$filename${NC}"
            } || echo -e "${YELLOW}${BOLD}[iOF]${NC} ${YELLOW}未识别可执行文件${NC}"
            ;;
    esac
    echo -e "${CYAN}${BOLD}文件路径:${NC} ${WHITE}$arch_dir${NC}"
}

# 主程序流程
show_welcome_and_select_mode

echo -e "${BLUE}${BOLD}[iOF]${NC} ${BLUE}正在检查系统依赖...${NC}"
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

arch_options=()
arch_files=()
arch_details=()
extract_linux_options
select_architecture
download_and_install

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}[iOF]${NC} ${GREEN}安装(下载)完成！${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"