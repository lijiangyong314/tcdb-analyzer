```markdown
# TCDB DIAMOND Result Analyzer / TCDB DIAMOND 结果分析器

> **Disclaimer / 免责声明**
>
> This tool is provided "as is", without warranty of any kind, express or implied. The author(s) do not guarantee the correctness, completeness, or reliability of the analysis results. This tool is intended as a helper utility only — users are solely responsible for verifying all output before using it in any research, publication, or decision-making process.
>
> 本工具按"原样"提供，不提供任何形式的明示或暗示担保。作者不对分析结果的正确性、完整性或可靠性作任何保证。本工具仅作为辅助工具，用户在使用任何分析结果用于研究、发表或决策之前，须自行验证所有输出。

---

## Prerequisites / 前置要求

> **⚠️ READ THIS FIRST / 请先阅读此部分**

### System Requirements / 系统要求

| Requirement / 要求 | Details / 说明 |
|-------------------|----------------|
| **OS / 操作系统** | Linux / WSL (Windows Subsystem for Linux) — see notes below / 见下方备注 |
| **Bash** | 3.2+ (tested: GNU Bash 4.4 / 5.0; macOS default 3.2 may work but not fully tested) / 3.2+（测试通过：GNU Bash 4.4 / 5.0；macOS 默认 3.2 可能可用但未充分测试） |
| **AWK** | gawk recommended (tested: GNU Awk 5.0+) / 推荐 gawk（测试通过：GNU Awk 5.0+） |
| **DIAMOND** | 2.x — 用于生成输入文件 |

> **Not supported / 不支持：**
> - Native Windows CMD / PowerShell (use WSL or Git Bash / 使用 WSL 或 Git Bash)
> - macOS default `sort` (the script uses `sort -g` for numeric sorting; BSD `sort` lacks `-g` and will fail)
> - macOS 自带的 `sort`（脚本使用了 `sort -g`，BSD `sort` 不支持此选项，会报错）
> - macOS default Bash (ships Bash 3.2; the script does not use associative arrays and may work on 3.2, but `sort -g` remains an issue)
> - macOS 默认 Bash（自带 3.2；脚本未使用关联数组，可能可用，但 `sort -g` 问题仍需解决）
>
> **macOS workaround / macOS 解决方案：**
>
> 1. **Install GNU coreutils** (provides `gsort` with `-g` support)  
>    **安装 GNU coreutils**（提供支持 `-g` 的 `gsort`）：
>    ```bash
>    brew install coreutils
>    # Add GNU tools to PATH (temporarily)
>    export PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
>    ```
>
> 2. **Optional: Install a newer Bash** (not strictly required but recommended)  
>    **可选：安装新版 Bash**（非必需，但推荐）：
>    ```bash
>    brew install bash
>    /opt/homebrew/bin/bash --version  # verify >= 4.0
>    ```
>
> 3. **Run the script with the updated environment**  
>    **在更新后的环境中运行脚本：**
>    ```bash
>    export PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
>    /opt/homebrew/bin/bash tcdb_analyzer_v2.7.2.sh -i ...
>    ```
>
> **v2.7.2 Note / v2.7.2 注意：** As of this version, `check_dependencies()` includes an automatic `sort -g` capability test. If your `sort` does not support `-g`, the script will exit with a clear error message and suggest installing GNU coreutils.
>
> 自 v2.7.2 起，`check_dependencies()` 包含自动 `sort -g` 兼容性检测。如果你的 `sort` 不支持 `-g`，脚本会给出明确报错并建议安装 GNU coreutils。

**No other dependencies / 无其他依赖：** 纯 Bash + AWK，无需 R / Python / 其他解释器。

### ⚠️ DIAMOND Input Format / DIAMOND 输入格式（必须遵守）

**Your DIAMOND output MUST use 13-column format with `stitle` as the last column. Otherwise this tool will NOT work.**

**你的 DIAMOND 输出必须使用 13 列格式，且最后一列必须是 `stitle`。否则本工具无法工作。**

```bash
# ✅ Correct / 正确
diamond blastp -q queries.faa -d tcdb.dmnd -o results.tsv \
  --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore stitle

# ❌ Wrong / 错误 — column 13 is `qlen`, not `stitle`
diamond blastp -q queries.faa -d tcdb.dmnd -o results.tsv --outfmt 6
```

| | Column 13 / 第 13 列 |
|---|---|
| ✅ Correct / 正确 | `stitle` (target description, contains TC number / 目标描述，含 TC 编号) |
| ❌ Wrong / 错误 | `qlen` (query length / 查询序列长度) |

---

## Overview / 概述

**English:**
Parse DIAMOND BLASTP results against the TCDB (Transporter Classification Database) to automatically extract TC numbers, annotate transporter classes, and generate summary statistics.

**中文：**
从针对 TCDB（转运蛋白分类数据库）的 DIAMOND BLASTP 比对结果中，自动提取 TC 编号、注释转运蛋白分类，并生成统计报告。

**GitHub:** [https://github.com/lijiangyong314](https://github.com/lijiangyong314)

---

## Quick Start / 快速开始

```bash
# Default: E-value < 1e-6, best hit per protein, TSV output
# 默认：E-value < 1e-6，每蛋白保留最佳 hit，输出 TSV
./tcdb_analyzer_v2.7.2.sh -i diamond_results.tsv -d tcdb.faa -o output

# Also generate CSV alongside TSV
# 同时生成 CSV 和 TSV
./tcdb_analyzer_v2.7.2.sh -i diamond_results.tsv -d tcdb.faa -o output -x

# Stricter filtering
# 更严格的过滤条件
./tcdb_analyzer_v2.7.2.sh -i diamond_results.tsv -d tcdb.faa -o output -e 1e-8 -l 100 -b 100

# Keep all hits (no deduplication), CSV only
# 保留所有 hit（不去重），只输出 CSV
./tcdb_analyzer_v2.7.2.sh -i diamond_results.tsv -d tcdb.faa -o output -a -f csv
```

---

## Installation / 安装

**English:**
Download the script and make it executable:

**中文：**
下载脚本后赋予执行权限即可：

```bash
chmod +x tcdb_analyzer_v2.7.2.sh
```

> See [Prerequisites / 前置要求](#prerequisites--前置要求) for system requirements.
> 系统要求见 [Prerequisites / 前置要求](#prerequisites--前置要求)。

---

## Input / 输入文件

### DIAMOND Result File (`-i`) / DIAMOND 结果文件

**English:**
The DIAMOND output **must** be generated with the following 13-column format. The 13th column (`stitle`) is required for TC number extraction.

**中文：**
DIAMOND 输出**必须**使用以下 13 列格式生成。第 13 列（`stitle`）用于提取 TC 编号。

```bash
diamond blastp -q queries.faa -d tcdb.dmnd -o results.tsv \
  --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore stitle
```

> **⚠️ Important / 重要：** Do NOT use standard `--outfmt 6` (which has `qlen` as column 13). The script will fail to extract TC numbers.
>
> **⚠️ 重要：** 不要使用标准的 `--outfmt 6`（其第 13 列为 `qlen`），否则脚本无法提取 TC 编号。

**Column reference / 列说明：**

| Col / 列 | Field / 字段 | Description / 说明 |
|-----------|--------------|-------------------|
| 1 | `qseqid` | Query protein ID / 查询蛋白 ID |
| 2 | `sseqid` | Target sequence ID / 目标序列 ID |
| 3 | `pident` | Percent identity / 一致性百分比 |
| 4 | `length` | Alignment length / 比对长度 |
| 5 | `mismatch` | Mismatch count / 错配数 |
| 6 | `gapopen` | Gap openings / 空位数 |
| 7-8 | `qstart/qend` | Query start/end / 查询起止 |
| 9-10 | `sstart/send` | Target start/end / 目标起止 |
| 11 | `evalue` | E-value / E 值 |
| 12 | `bitscore` | Bit score / 比特分数 |
| **13** | **`stitle`** | **Target description (contains TC#) / 目标描述（含 TC 编号）** |

### TCDB Database File (`-d`) / TCDB 数据库文件

**English:**
A FASTA file containing TCDB sequences. Used to validate TC numbers extracted from DIAMOND results. Download from:

**中文：**
包含 TCDB 序列的 FASTA 文件，用于验证从 DIAMOND 结果中提取的 TC 编号。下载地址：

```bash
wget -O tcdb.faa "https://www.tcdb.org/public/tcdb"
```

> **Note / 注意：** The above URL may change. If it fails, please visit [TCDB official download page](https://www.tcdb.org/) to obtain the current FASTA file.
>
> **⚠️ 注意：** 上述链接可能失效。如无法下载，请访问 [TCDB 官方下载页](https://www.tcdb.org/) 获取最新的 FASTA 文件。

---

## Parameters / 参数说明

| Parameter / 参数 | Default / 默认值 | Description / 说明 |
|-------------------|-----------------|-------------------|
| `-i` | *(required)* | DIAMOND output file / DIAMOND 输出文件 **（必填）**；v2.7.2 起支持 `.gz` 压缩格式 |
| `-d` | *(required)* | TCDB FASTA file (for TC validation) / TCDB FASTA 文件（用于验证 TC 编号） **（必填）** |
| `-o` | *(required)* | Output file prefix / 输出文件前缀 **（必填）** |
| `-e` | `1e-6` | E-value threshold (strict `<`) / E-value 阈值（严格小于） |
| `-l` | `1` | Minimum alignment length / 最小比对长度 |
| `-b` | `0` | Minimum bitscore / 最小比特分数 |
| `-p` | `yes` | Include Class 9 (9.A/9.B, uncharacterized) / 是否包含第 9 类（9.A/9.B，未表征家族）。`yes` or / 或 `no` |
| `-a` | `no` | Keep all hits (no deduplication) / 保留所有 hit（不去重）。`yes` or / 或 `no` |
| `-f` | `tsv` | Output format / 输出格式：`tsv` or / 或 `csv` |
| `-x` | `no` | Generate both TSV and CSV / 同时生成 TSV 和 CSV。`yes` or / 或 `no` |

---

## Output Files / 输出文件

| File / 文件 | Description / 说明 |
|-------------|-------------------|
| `*_assignment.tsv /.csv` | Detailed annotation per protein / 每个蛋白的详细注释信息 |
| `*_summary.tsv /.csv` | Class-level + Subclass-level counts / Class 级 + Subclass 级统计汇总 |

### Output Column Reference / 输出列说明

**`*_assignment.tsv` / 详细注释文件：**

| Column / 列 | Field / 字段 | Description / 说明 |
|-------------|--------------|-------------------|
| 1 | `Protein_ID` | Query protein ID / 查询蛋白 ID |
| 2 | `TC_Number` | Full TC number (e.g. `3.A.1.106.12`) / 完整 TC 编号 |
| 3 | `TC_Class` | TC Class (1-9) / TC 类别（1-9） |
| 4 | `TC_Subclass` | TC Subclass (e.g. `3.A`) / TC 子类 |
| 5 | `TC_Family` | TC Family / TC 家族 |
| 6 | `Is_Standard` | `1` = standard TC, `0` = non-standard format / `1`=标准格式，`0`=非标准格式 |
| 7 | `Evalue` | E-value of this hit / 该 hit 的 E-value |
| 8 | `Bitscore` | Bitscore of this hit / 该 hit 的比特分数 |

**`*_summary.tsv` / 统计汇总文件：**

| Column / 列 | Field / 字段 | Description / 说明 |
|-------------|--------------|-------------------|
| 1 | `Level` | `Class` or `Subclass` / `Class` 或 `Subclass` |
| 2 | `ID` | Class or Subclass ID / Class 或 Subclass 编号 |
| 3 | `Label` | Human-readable label / 可读标签（如 `Channels_Pores`） |
| 4 | `Count` | Number of proteins in this category / 该类别中的蛋白数量 |

---

## TC Class Reference / TC 类别参考

> **Note / 注意：** Class 6 and Class 7 are **reserved (unassigned)** in the TCDB classification system. They contain no actual transporter families and will never appear in analysis results. The script correctly excludes them from class labels.
>
> Class 6 和 Class 7 在 TCDB 分类体系中为**预留编号**，未分配任何实际转运蛋白家族，永远不会出现在分析结果中。脚本正确地不包含它们的标签映射。

| Class / 类别 | Label / 标签 | Description / 说明 |
|--------------|--------------|-------------------|
| 1 | `Channels_Pores` | Channels and pores / 通道与孔蛋白 |
| 2 | `Electrochem_Driven` | Electrochemical potential-driven transporters / 电化学势驱动转运蛋白 |
| 3 | `Primary_Active` | Primary active transporters / 原主动转运蛋白 |
| 4 | `Group_Translocators` | Group translocators / 基团转运蛋白 |
| 5 | `TM_Electron_Carriers` | Transmembrane electron carriers / 跨膜电子载体 |
| 6 | — | Reserved (no families assigned) / 预留（未分配家族） |
| 7 | — | Reserved (no families assigned) / 预留（未分配家族） |
| 8 | `Accessory_Factors` | Accessory factors involved in transport / 转运辅助因子 |
| 9 | `Uncharacterized` | Functionally uncharacterized transporters / 功能未表征转运蛋白 |

> Class 9 is included by default. Use `-p no` to exclude.
> 第 9 类默认包含，使用 `-p no` 可排除。

---

## Best Hit Strategy / 最佳 Hit 策略

**English:**
By default (`-a no`), the script keeps only the best hit per query protein:
1. After E-value / length / bitscore filtering, group by `qseqid`
2. Sort by E-value (ascending), then by bitscore (descending)
3. Keep only the top-ranked hit for each protein

Use `-a yes` to keep all passing hits without deduplication.

**中文：**
默认情况下（`-a no`），脚本对每个查询蛋白只保留最佳 hit：
1. E-value / 长度 / bitscore 过滤后，按 `qseqid` 分组
2. 按 E-value（升序）、再按 bitscore（降序）排序
3. 每个蛋白只保留排名第一的 hit

使用 `-a yes` 可保留所有通过过滤的 hit，不去重。

---

## E-value Comparison / E-value 比较说明

**English:**
E-value comparison uses `-log10` transformation for reliable handling of scientific notation (e.g. `1e-50`, `1e-6`) across different AWK implementations (gawk/mawk/BusyBox). The comparison is strict: only hits with E-value **strictly less than** the threshold are kept.

**中文：**
E-value 比较使用 `-log10` 转换，以可靠处理科学计数法（如 `1e-50`、`1e-6`），兼容不同 AWK 实现（gawk/mawk/BusyBox）。比较是严格的：只保留 E-value **严格小于**阈值的 hit。

| Threshold / 阈值 | Kept / 保留 | Filtered / 过滤 |
|-----------------|-------------|-----------------|
| `-e 1e-6` | `1e-50`, `1e-10`, `1e-7` | `1e-6`, `1e-5`, `1e-3` |

---

## Examples / 示例

### Example 1: Basic usage / 基本用法

```bash
./tcdb_analyzer_v2.7.2.sh \
  -i diamond_out.tsv \
  -d tcdb.faa \
  -o results
```

### Example 2: Exclude uncharacterized (Class 9) / 排除未表征家族（第 9 类）

```bash
./tcdb_analyzer_v2.7.2.sh \
  -i diamond_out.tsv \
  -d tcdb.faa \
  -o results \
  -p no
```

### Example 3: Strict filtering + dual output / 严格过滤 + 双格式输出

```bash
./tcdb_analyzer_v2.7.2.sh \
  -i diamond_out.tsv \
  -d tcdb.faa \
  -o results \
  -e 1e-10 \
  -l 50 \
  -b 50 \
  -x
```

### Example 4: Keep all hits for downstream analysis / 保留所有 hit 用于下游分析

```bash
./tcdb_analyzer_v2.7.2.sh \
  -i diamond_out.tsv \
  -d tcdb.faa \
  -o results \
  -a yes \
  -f csv
```

---

## Troubleshooting / 故障排除

### Empty output / 输出为空

**English:**
Check the following in order:
1. Did you use the correct DIAMOND `--outfmt 6` with 13 columns (ending in `stitle`)?
2. Are there any hits passing the E-value threshold? Try `-e 1e-3` to test.
3. Does the TCDB FASTA file contain valid TC numbers in headers?

**中文：**
按顺序检查以下几点：
1. 是否使用了正确的 DIAMOND `--outfmt 6`（13 列，以 `stitle` 结尾）？
2. 是否有任何 hit 通过 E-value 阈值？可尝试 `-e 1e-3` 测试。
3. TCDB FASTA 文件的序列头是否包含有效的 TC 编号？

### "command not found: diamond" / "diamond 命令未找到"

Install DIAMOND first: / 先安装 DIAMOND：
```bash
conda install -c bioconda diamond
# or / 或
wget https://github.com/bbuchfink/diamond/releases/latest/download/diamond-linux64.tar.gz
```

### TC numbers not extracted / TC 编号未提取

**English:**
The script extracts TC numbers from the `stitle` column using regex. Supported formats:
- `1.A.1.1.1` (5-segment, standard)
- `1.A.1.1` (4-segment, e.g. some Class 9 entries)
- `TC#1.A.1.1.1` or `TC 1.A.1.1.1` (with prefix)

**中文：**
脚本使用正则表达式从 `stitle` 列提取 TC 编号，支持格式：
- `1.A.1.1.1`（5 段，标准格式）
- `1.A.1.1`（4 段，如部分 Class 9 条目）
- `TC#1.A.1.1.1` 或 `TC 1.A.1.1.1`（带前缀）

### macOS: "sort: invalid option -- g" / macOS 上报错 `sort: invalid option -- g`

**English:**
As of v2.7.2, the script automatically detects `sort -g` support in `check_dependencies()` and exits with a clear error message if unavailable. Install GNU coreutils and prepend its bin directory to PATH (see [macOS workaround](#prerequisites--前置要求)).

**中文：**
自 v2.7.2 起，脚本在 `check_dependencies()` 中自动检测 `sort -g` 支持，不支持则给出明确报错并退出。请安装 GNU coreutils 并将其 bin 目录添加到 PATH（参见 [macOS 解决方案](#prerequisites--前置要求)）。

---

## Version History / 版本历史

| Version / 版本 | Date / 日期 | Notes / 说明 |
|---------------|------------|--------------|
| `v2.7.2` | 2026-06-01 | **Bug fixes / Bug 修复：**[1] 修复 `TEMP_FILES` 数组逗号语法错误导致临时文件残留；[2] 新增 `sort -g` 跨平台兼容性自动检测；[3] TC 编号正则放宽为 4-5 段，兼容非标准 Class 9 条目；[4] 支持 `.gz` 压缩输入文件 |
| `v2.7.1` | 2026-05-30 | Fixed E-value comparison logic (safe_evalue_cmp), fixed cleanup on empty TEMP_FILES, removed dead code in extract_tc() / 修复 E-value 比较逻辑，修复空 TEMP_FILES 时 cleanup 报错，移除 extract_tc() 死代码 |
| `v2.7.0` | 2026-05-28 | Previous release / 上一版本 |
| `v2.x` | 2026-05 | Major rewrite with strict bash mode (`set -euo pipefail`) / 使用严格 bash 模式重写 |

---

## License / 许可证

**English:**
This project is provided for academic and research purposes. Feel free to modify and redistribute with attribution.

**中文：**
本工具供学术和研究用途使用。欢迎修改和再分发，请注明出处。

---

## Citation / 引用

If you use this tool in a publication, please cite / 如在发表中使用本工具，请引用：

> TCDB: Saier MH et al., *Nucleic Acids Res*, 2024. https://doi.org/10.1093/nar/gkad975
>
> DIAMOND: Buchfink B et al., *Nature Methods*, 2021. https://doi.org/10.1038/s41592-021-01101-x

---

## Author / 作者

**Jiangyong Li /李将勇**
- GitHub: [@lijiangyong314](https://github.com/lijiangyong314)
```
