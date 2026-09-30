# 配体、受体处理与对接流程

## 一、受体模型整理

1. 选择 SPP1 模型，保留成熟蛋白部分，即 UniProt 残基 17–314、A 链。
2. 将选定的 CIF 模型转换为 PDB，并确认残基编号与上述区间一致，pLDDT 保留在 B-factor 列中。
3. 使用 MGLTools 对应的 Python 运行 `scripts/prepare_receptor_kollman.py`。脚本修复键和氢，添加 Kollman 电荷，清理非极性氢、孤对电子、水和非标准残基，输出刚性受体 PDBQT。
4. 核对原子数、残基数、链标识、氢原子、原子类型和总电荷，参照 `docs/receptor_processing_report.txt`。

现存受体脚本从已整理好的 PDB 开始处理。CIF 转换、成熟蛋白整理及编号恢复记录在此流程中，但对应独立代码未收录。

## 二、配体处理

`prepare_ligands.ps1` 逐条读取 SDF，执行以下步骤：

- 修复部分异常的 V2000 原子数、键数计数行。
- 从 `CdId`、`ID` 或 `Name` 提取标识，以五位记录序号和标识组成文件名。
- 按输入原子数设置超时：不超过 50 个原子使用基础时限，51–100 个使用两倍，更多使用三倍。
- 使用 Open Babel，在 pH 7.4 条件下生成三维构象，并进行能量最小化。
- 按 MMFF94s、MMFF94、UFF 的顺序尝试可用力场，排除坐标全部为零的输出。
- 使用 Gasteiger 部分电荷将处理后的 SDF 转换为 PDBQT。
- 检查原子记录、`TORSDOF` 和坐标，汇总原子数与总电荷。
- 保存处理后的 SDF、PDBQT、日志、失败输入副本及汇总表。
- 除非指定 `-Force`，否则跳过符合现有检查条件的有效输出。

### 常用参数

| 参数 | 含义 | 默认值 |
| --- | --- | --- |
| `-InputSdf` | 输入的多分子 SDF | 输出目录中的 `input.sdf` |
| `-OutputRoot` | 配体输出目录 | 当前目录下的 `ligand_data` |
| `-OpenBabelPath` | Open Babel 可执行文件名或路径 | `obabel` |
| `-OpenBabelDataDir` | Open Babel 数据目录 | 当前目录下的 `openbabel_data` |
| `-ThrottleLimit` | 并行任务数量 | 36 |
| `-TimeoutSeconds` | 基础超时时间，单位为秒 | 120 |
| `-MinimizeSteps` | 能量最小化步数 | 1000 |
| `-SummaryName` | 输出汇总文件名 | `summary.csv` |

### 重试与结果保留

- `-OnlyFailed`：根据输出目录已有的 `summary.csv`，只重试失败记录。
- `-OnlyTimeouts`：只重试错误中含 `TIMEOUT` 的失败记录。
- `-RecoveryMode`：先独立生成三维构象，再使用 MMFF94s/UFF 最小化。
- `-NoTimeout`：不设置超时限制。
- `-Force`：重新生成输出。

重试汇总表只包含本次选择的记录。建议指定 `-SummaryName summary_retry.csv` 等独立名称；核对结果并备份后，再按 `Index` 合并到主汇总表。当前仓库未提供自动合并脚本。

## 三、分子对接

同一比较集使用相同的受体与对接盒。修改 `configs/vina_config_cpu16.txt` 中的受体路径，并按机器实际资源选择 CPU 数量。`configs/batch.conf` 提供此前使用的另一份配置。

本次配置中的对接盒中心为 `(-17.2, -52.6, 19.8)` Å，边长为 `30 × 30 × 30` Å，`exhaustiveness=16`、`num_modes=10`。批量任务需另行提供配体列表及启动命令；配置文件本身不负责遍历全部配体。

## 四、评分汇总与清理

Vina 结束后，汇总脚本从构象文件前 20 行提取第一个 `REMARK VINA RESULT`，按评分从低到高排序。输出列为 `File`（文件名）、`LigandName`（配体名）及 `BestAffinity_kcal_mol`（最佳评分，单位 kcal/mol）。

单进程汇总可用 `-VinaPid` 指定要等待的进程；多进程汇总可用 `-ProcessIds` 传入进程编号数组。默认不等待进程。输出目录需预先存在。

`cleanup_historical.ps1` 依据主汇总表中的 `success` 和 `skipped_existing` 状态保留有效 SDF/PDBQT，清理其他结构文件，以及失败副本、历史测试汇总表和配体日志。运行前先备份需要保留的日志，并确认主汇总表覆盖全部有效记录。

## 五、质控要点

解释评分前应核对：

- 选中的配体 PDBQT 非空，具有原子记录和 `TORSDOF`。
- 配体坐标不全部为零；这一检查不能替代完整的几何和立体化学质量评估。
- Vina 中的受体、配体路径指向预期文件。
- 比较集使用同一对接盒。
- 失败或超时记录已排除，或完成恢复与重新核验。
- 汇总文件来自已完成并核验的对接输出；仅存在评分行不足以证明批量任务全部完成。

