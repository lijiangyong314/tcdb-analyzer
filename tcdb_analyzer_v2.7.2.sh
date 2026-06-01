#!/usr/bin/env bash

# ============================================================
# TCDB DIAMOND 结果分析器 - 标准版 (v2.7.2)
#
# 功能:
#   - 默认参数对齐经典分析: E-value<1e-6, 无长度/Bitscore过滤, 包含Class 9, 每蛋白最佳Hit
#   - 统计输出: Class 级 和 Subclass 级 (不包含Family级)
#   - 用户可自定义过滤参数 (-e, -l, -b, -p, -a)
#
# v2.7.2 修复:
#   - [Fix #1] 数组追加语法错误（逗号→空格）
#   - [Fix #3] sort -g 跨平台兼容性检测
#   - [Fix #5] TC 编号正则放宽为 4-5 段，兼容 Class 9 非标准条目
#   - [Fix #6] 支持 .gz 压缩输入文件
# ============================================================

set -euo pipefail

# ---------- 默认参数 (对齐公司) ----------
EVALUE="1e-6"
MIN_LEN="1"                # 不过滤长度
MIN_BITSCORE="0"           # 不过滤bitscore
INCLUDE_PUTATIVE="yes"     # 包含9类
FORMAT="tsv"
EXTRA_CSV="no"
KEEP_ALL="no"              # 最佳Hit
TCDB_FAA=""
INPUT=""
OUTPUT_DIR=""
SEP=$'\t'

# ---------- 临时文件清理 ----------
TEMP_FILES=()
cleanup() {
    [ ${#TEMP_FILES[@]} -gt 0 ] && rm -f "${TEMP_FILES[@]}"
}
trap cleanup EXIT

# ---------- 日志函数 ----------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法: $0 -i <diamond.tsv> -d <tcdb.faa> -o <output_dir> [选项]

必选:
  -i FILE   DIAMOND输出 (13列, 制表符分隔, 第13列包含TC编号; 支持 .gz 压缩)
  -d FILE   官方TCDB数据库 (tcdb.faa)
  -o DIR    输出目录

可选:
  -f FORMAT [csv|tsv] (默认: tsv)
  -x        同时输出TSV和CSV (覆盖 -f)
  -e EVAL   E-value阈值 (默认: 1e-6)
  -l LEN    最小比对长度 (默认: 1, 即无限制)
  -b SCORE  最小Bitscore (默认: 0, 即无限制)
  -p FLAG   [yes|no] 包含9.A/9.B (默认: yes)
  -a        保留所有通过过滤的Hit (不去重); 默认每个蛋白只保留最佳Hit
  -h        显示帮助

注意:
  - 默认参数复现经典分析: E-value<1e-6, 无额外过滤, 包含9类, 每蛋白最佳Hit。
  - 统计输出仅包含 Class 和 Subclass 两个层级。
EOF
    exit 1
}

# ---------- 参数解析 ----------
parse_args() {
    while getopts "i:d:o:f:e:l:b:p:xah" opt; do
        case "${opt}" in
            i) INPUT="${OPTARG}" ;;
            d) TCDB_FAA="${OPTARG}" ;;
            o) OUTPUT_DIR="${OPTARG}" ;;
            f) FORMAT="${OPTARG}" ;;
            e) EVALUE="${OPTARG}" ;;
            l) MIN_LEN="${OPTARG}" ;;
            b) MIN_BITSCORE="${OPTARG}" ;;
            p) INCLUDE_PUTATIVE="${OPTARG}" ;;
            x) EXTRA_CSV="yes" ;;
            a) KEEP_ALL="yes" ;;
            h) show_help ;;
            *) show_help ;;
        esac
    done

    if [ -z "${INPUT}" ] || [ -z "${TCDB_FAA}" ] || [ -z "${OUTPUT_DIR}" ]; then
        log_error "缺少必选参数"
        show_help
    fi

    if [ "${EXTRA_CSV}" = "yes" ]; then
        FORMAT="both"
    fi
}

# ---------- 参数验证 ----------
validate_params() {
    log_info "验证参数..."

    [ ! -f "${INPUT}" ] && { log_error "输入文件不存在: ${INPUT}"; exit 1; }
    [ ! -f "${TCDB_FAA}" ] && { log_error "TCDB数据库不存在: ${TCDB_FAA}"; exit 1; }
    mkdir -p "${OUTPUT_DIR}" || { log_error "无法创建输出目录: ${OUTPUT_DIR}"; exit 1; }

    if [ "${FORMAT}" != "both" ]; then
        if [[ ! "${FORMAT}" =~ ^(csv|tsv)$ ]]; then
            log_error "-f 必须是 csv 或 tsv"; exit 1;
        fi
    fi

    if [ "${FORMAT}" = "csv" ]; then
        SEP=","
    else
        SEP=$'\t'
    fi

    case "${INCLUDE_PUTATIVE}" in yes|no) ;; *) log_error "-p 必须是 yes 或 no"; exit 1 ;; esac
    case "${KEEP_ALL}" in yes|no) ;; *) log_error "内部错误: KEEP_ALL 值无效"; exit 1 ;; esac

    for var in MIN_LEN MIN_BITSCORE; do
        val="${!var}"
        if [[ ! "${val}" =~ ^[0-9]+$ ]]; then
            log_error "${var}=${val} 必须是非负整数"; exit 1
        fi
    done

    if [[ ! "${EVALUE}" =~ ^[0-9.eE+-]+$ ]]; then
        log_error "无效的E-value格式: ${EVALUE}"; exit 1
    fi

    log_info "参数验证通过"
    log_info "过滤条件: E-value<${EVALUE}, Len>=${MIN_LEN}, Bitscore>=${MIN_BITSCORE}"
    log_info "包含9.A/9.B: ${INCLUDE_PUTATIVE}"
    if [ "${KEEP_ALL}" = "yes" ]; then
        log_info "模式: 保留所有通过过滤的Hit (不去重)"
    else
        log_info "模式: 每个蛋白只保留最佳Hit (E-value最小, 同E-value取Bitscore最大)"
    fi
}

# ---------- 依赖检查 ----------
check_dependencies() {
    log_info "检查依赖..."
    for cmd in awk sort grep sed cut head mktemp; do
        command -v "${cmd}" >/dev/null 2>&1 || { log_error "依赖未找到: ${cmd}"; exit 1; }
    done

    # [Fix #3] 检测 sort -g 跨平台兼容性 (GNU coreutils 扩展)
    if ! echo "1e-10" | sort -g >/dev/null 2>&1; then
        log_error "当前系统的 sort 命令不支持通用数值排序（-g）"
        log_error "TCDB 分析器需要使用 GNU coreutils 中的 sort"
        log_error "macOS 用户可通过 Homebrew 安装: brew install coreutils"
        exit 1
    fi
}

# ---------- 输入文件格式验证 ----------
validate_input_format() {
    log_info "验证输入文件格式..."

    # 根据输入文件类型选择读取命令（支持 .gz）
    local input_cmd="cat"
    if [[ "${INPUT}" == *.gz ]]; then
        input_cmd="zcat"
    fi

    local first_line
    first_line=$(${input_cmd} "${INPUT}" | grep -v '^#' | head -n 1) || true
    if [ -z "${first_line}" ]; then
        log_error "输入文件无有效数据行"
        exit 1
    fi
    local col_count
    col_count=$(echo "${first_line}" | awk -F'\t' '{print NF}')
    if [ "${col_count}" -ne 13 ]; then
        log_error "列数错误: ${col_count} (应为13)"
        exit 1
    fi
    log_info "输入格式正确 (13列)"
}

# ---------- 构建TCDB验证集 ----------
build_tcdb_index() {
    log_info "构建TCDB验证集..."
    local tc_index="${OUTPUT_DIR}/.tcdb_index.tmp"
    TEMP_FILES+=("${tc_index}")
    grep "^>" "${TCDB_FAA}" 2>/dev/null | \
        grep -oE '[0-9]+\.[A-Z]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
        sort -u > "${tc_index}" || true

    if [ ! -s "${tc_index}" ]; then
        log_error "无法从TCDB数据库提取TC编号"
        exit 1
    fi
    local count
    count=$(wc -l < "${tc_index}")
    log_info "已加载 ${count} 个官方TC编号"
    echo "${tc_index}"
}

# ---------- 核心分析 (生成数据和统计) ----------
run_analysis() {
    local tc_index="$1"
    local out_prefix="$2"
    local assignment_file="${out_prefix}.${FORMAT/ both/tsv}"
    local summary_file="${out_prefix}_summary.${FORMAT/ both/tsv}"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    local tmp_raw tmp_final tmp_class tmp_subclass tmp_summary
    tmp_raw=$(mktemp)
    tmp_class=$(mktemp)
    tmp_subclass=$(mktemp)
    tmp_summary=$(mktemp)
    # [Fix #1] 数组元素用空格分隔，不是逗号
    TEMP_FILES+=("${tmp_raw}" "${tmp_class}" "${tmp_subclass}" "${tmp_summary}")

    log_info "开始分析 (输出前缀: ${out_prefix})"

    # [Fix #6] 根据输入文件类型选择读取命令（支持 .gz）
    local input_cmd="cat"
    if [[ "${INPUT}" == *.gz ]]; then
        if command -v zcat >/dev/null 2>&1; then
            input_cmd="zcat"
        else
            log_error "输入文件为 .gz 压缩格式，但未找到 zcat 命令"
            exit 1
        fi
    fi

    # ----- 1. 原始过滤与TC提取 (不输出表头) -----
    # [Fix #5] TC 编号正则放宽为 4-5 段，兼容 Class 9 非标准条目 (如 9.B.14)
    ${input_cmd} "${INPUT}" | awk -v ev="${EVALUE}" -v ml="${MIN_LEN}" -v bs="${MIN_BITSCORE}" \
        -v inc_putative="${INCLUDE_PUTATIVE}" -v index_file="${tc_index}" '
    function extract_tc(s) {
        # 支持 4 到 5 段编号: N.LL.N.N 或 N.LL.N.N.N
        if (match(s, /[0-9]+\.[A-Z]+(\.[0-9]+){2,3}/))
            return substr(s, RSTART, RLENGTH);
        return "";
    }
    function safe_evalue_cmp(a, threshold) {
        # 将E-value转为 -log10 比较，避免科学计数法字符串解析不一致
        if (a + 0 == 0) return -1;    # E-value=0 永远通过
        if (threshold + 0 == 0) return -1; # 阈值=0 无意义，放行
        la = -log(a + 0) / log(10);
        lt = -log(threshold + 0) / log(10);
        return (la > lt) ? -1 : 1;   # -1 表示 a < threshold (更小E-value更好)
    }
    BEGIN {
        FS = "\t"; OFS = "\t";
        while ((getline tc < index_file) > 0) valid[tc] = 1;
        close(index_file);
    }
    /^$/ || /^#/ { next; }
    NF != 13 { next; }
    {
        qseqid = $1;
        evalue = $11;
        bitscore = $12;
        aln_len = $4;
        desc = $13;

        if (safe_evalue_cmp(evalue, ev) >= 0) next;
        if (aln_len + 0 < ml) next;
        if (bitscore + 0 < bs) next;

        tc_full = extract_tc(desc);
        if (tc_full == "") next;

        is_std = (tc_full in valid) ? 1 : 0;
        split(tc_full, tc_parts, ".");
        if (inc_putative == "yes" && tc_parts[1] == "9" && tc_parts[2] ~ /^[AB]+$/) is_std = 1;
        if (inc_putative == "no" && tc_parts[1] == "9" && tc_parts[2] ~ /^[AB]+$/) next;

        tc_class = tc_parts[1];
        tc_subclass = tc_parts[1] "." tc_parts[2];   # 只取到 subclass，例如 "3.A"
        # 保留完整 family 用于详细输出（但统计不用）
        tc_family = tc_parts[1] "." tc_parts[2] "." tc_parts[3];

        print qseqid, tc_full, tc_class, tc_subclass, tc_family, is_std, evalue, bitscore;
    }' > "${tmp_raw}"

    # 表头内容
    local header_data
    header_data=$(cat <<EOF
# Generated: ${timestamp}
# Tool: TCDB Analyzer v2.7.2
# Filters: E-value<${EVALUE}, Len>=${MIN_LEN}, Bitscore>=${MIN_BITSCORE}
# Include 9.A/9.B: ${INCLUDE_PUTATIVE}
Protein_ID	TC_Number	TC_Class	TC_Subclass	TC_Family	Is_Standard	Evalue	Bitscore
EOF
)

    if [ ! -s "${tmp_raw}" ]; then
        log_warn "无记录通过过滤"
        # 输出只有表头的文件
        if [ "${FORMAT}" = "both" ]; then
            echo -e "${header_data}" > "${out_prefix}.tsv"
            echo -e "Level\tID\tLabel\tCount" > "${out_prefix}_summary.tsv"
            tr '\t' ',' < "${out_prefix}.tsv" > "${out_prefix}.csv" 2>/dev/null || true
            tr '\t' ',' < "${out_prefix}_summary.tsv" > "${out_prefix}_summary.csv" 2>/dev/null || true
        elif [ "${FORMAT}" = "csv" ]; then
            echo -e "${header_data//\t/,}" > "${out_prefix}.csv"
            echo -e "Level,ID,Label,Count" > "${out_prefix}_summary.csv"
        else
            echo -e "${header_data}" > "${out_prefix}.tsv"
            echo -e "Level\tID\tLabel\tCount" > "${out_prefix}_summary.tsv"
        fi
        return
    fi

    # ----- 2. 去重或保留所有 -----
    tmp_final=$(mktemp)
    TEMP_FILES+=("${tmp_final}")
    if [ "${KEEP_ALL}" = "yes" ]; then
        cp "${tmp_raw}" "${tmp_final}"
        log_info "保留所有Hit: $(wc -l < "${tmp_final}") 条记录"
    else
        sort -t$'\t' -k1,1 -k7,7g -k8,8nr "${tmp_raw}" | \
            awk -F'\t' '!seen[$1]++' > "${tmp_final}"
        log_info "去重后蛋白数: $(wc -l < "${tmp_final}"), 原始Hit数: $(wc -l < "${tmp_raw}")"
    fi

    # ----- 3. 统计汇总 (Class 和 Subclass，不含 Family) -----
    log_info "生成统计报告 (Class 和 Subclass 层级)..."
    awk -v tmp_class="${tmp_class}" -v tmp_subclass="${tmp_subclass}" '
    BEGIN {
        FS = "\t"; OFS = "\t";
        class_label["1"] = "Channels_Pores";
        class_label["2"] = "Electrochem_Driven";
        class_label["3"] = "Primary_Active";
        class_label["4"] = "Group_Translocators";
        class_label["5"] = "TM_Electron_Carriers";
        class_label["8"] = "Accessory_Factors";
        class_label["9"] = "Uncharacterized";
    }
    {
        class = $3;
        subclass = $4;
        class_count[class]++;
        subclass_count[subclass]++;
    }
    END {
        # Class 级别
        for (c in class_count) {
            label = (c in class_label) ? class_label[c] : "Other";
            print "Class" "\t" c "\t" label "\t" class_count[c] >> tmp_class;
        }
        # Subclass 级别
        for (sc in subclass_count) {
            print "Subclass" "\t" sc "\t" sc "\t" subclass_count[sc] >> tmp_subclass;
        }
    }' "${tmp_final}"

    # 构建最终汇总文件 (两个节)
    echo -e "Level\tID\tLabel\tCount" > "${tmp_summary}"
    if [ -s "${tmp_class}" ]; then
        echo -e "\n# === Class level ===" >> "${tmp_summary}"
        sort -t$'\t' -k2,2n "${tmp_class}" >> "${tmp_summary}"
    fi
    if [ -s "${tmp_subclass}" ]; then
        echo -e "\n# === Subclass level ===" >> "${tmp_summary}"
        sort -t$'\t' -k4,4nr "${tmp_subclass}" >> "${tmp_summary}"
    fi

    # ----- 4. 输出最终文件 -----
    if [ "${FORMAT}" = "both" ]; then
        local tsv_assign="${out_prefix}.tsv"
        local tsv_summary="${out_prefix}_summary.tsv"
        echo -e "${header_data}" > "${tsv_assign}"
        cat "${tmp_final}" >> "${tsv_assign}"
        cp "${tmp_summary}" "${tsv_summary}"
        # CSV
        tr '\t' ',' < "${tsv_assign}" > "${out_prefix}.csv"
        tr '\t' ',' < "${tsv_summary}" > "${out_prefix}_summary.csv"
        log_info "已生成 TSV 和 CSV 格式: ${out_prefix}"
    elif [ "${FORMAT}" = "csv" ]; then
        local csv_assign="${out_prefix}.csv"
        local csv_summary="${out_prefix}_summary.csv"
        echo -e "${header_data//\t/,}" > "${csv_assign}"
        tr '\t' ',' < "${tmp_final}" >> "${csv_assign}"
        tr '\t' ',' < "${tmp_summary}" > "${csv_summary}"
        log_info "已生成 CSV 格式: ${out_prefix}"
    else
        local tsv_assign="${out_prefix}.tsv"
        local tsv_summary="${out_prefix}_summary.tsv"
        echo -e "${header_data}" > "${tsv_assign}"
        cat "${tmp_final}" >> "${tsv_assign}"
        cp "${tmp_summary}" "${tsv_summary}"
        log_info "已生成 TSV 格式: ${out_prefix}"
    fi
}

# ---------- 主函数 ----------
main() {
    parse_args "$@"
    validate_params
    check_dependencies
    validate_input_format
    local tc_index
    tc_index=$(build_tcdb_index)
    run_analysis "${tc_index}" "${OUTPUT_DIR}/tcdb_assignment"
    log_info "所有分析完成！"
}

main "$@"
