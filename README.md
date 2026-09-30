# 配体与受体处理及分子对接流程

本仓库整理了此前 SPP1 分子对接中使用的处理流程、代码和配置，便于查阅与复用，主要包括：

1. 受体模型整理及 AutoDockTools 受体处理；
2. 配体 SDF 格式修复、三维构象生成、能量最小化和 PDBQT 转换；
3. AutoDock Vina 对接区域与运行参数配置；
4. 对接结果汇总和历史中间文件清理。

仓库收录脚本、配置模板和质控记录。原始配体库、结构模型、生成的分子文件、对接结果、运行日志和软件安装包保留在本地。

## 文件说明

| 文件或目录 | 用途 |
| --- | --- |
| `scripts/prepare_receptor_kollman.py` | 使用 AutoDockTools 处理受体，添加 Kollman 电荷 |
| `scripts/prepare_ligands.ps1` | 并行处理配体，支持超时控制、力场回退、格式检查与失败重试 |
| `scripts/cleanup_historical.ps1` | 根据配体汇总表清理历史文件 |
| `scripts/summarize_after_vina.ps1` | 汇总已生成构象的最佳 Vina 评分 |
| `scripts/summarize_after_parallel.ps1` | 等待多个对接进程后汇总评分 |
| `configs/` | SPP1 对接区域定义及 Vina 配置模板 |
| `docs/WORKFLOW.md` | 完整处理步骤与参数说明 |
| `docs/receptor_processing_report.txt` | 此前受体处理的质控记录 |

## 运行环境

- Windows 上的 PowerShell 7 或更高版本（命令通常为 `pwsh`）。
- Open Babel 3.1.x，及完整的配套数据目录。
- AutoDockTools/MGLTools，以及可导入 `MolKit` 和 `AutoDockTools` 的 Python 环境。
- AutoDock Vina 1.2.x。

这些软件需单独安装。代码中的命令、参数名和软件名称保留原样，便于复制运行。

## 快速使用

在仓库根目录执行以下命令；将 `path\to\...` 替换为实际路径。路径包含空格时须加引号，输出目录须提前建立。

```powershell
# 1. 处理已整理好的成熟受体 PDB（使用 MGLTools 对应的 Python）
python scripts/prepare_receptor_kollman.py `
  path\to\SPP1_2_model2_mature.pdb `
  path\to\receptor_processed\SPP1_2_model2_rigid.pdbqt

# 2. 批量处理配体（输入 SDF 需自行提供）
./scripts/prepare_ligands.ps1 `
  -InputSdf path\to\ligands.sdf `
  -OutputRoot path\to\ligand_data `
  -OpenBabelPath obabel `
  -OpenBabelDataDir path\to\openbabel_data `
  -ThrottleLimit 36 -MinimizeSteps 1000

# 3. 修改配置文件中的受体路径后，运行单个配体对接
vina --config configs/vina_config_cpu16.txt --ligand path\to\ligand.pdbqt --out path\to\pose.pdbqt

# 4. 汇总对接评分，并明确指定结果表和状态文件路径
./scripts/summarize_after_vina.ps1 `
  -PosesDir path\to\docking_results\poses `
  -OutputCsv path\to\docking_results\best_affinity.csv `
  -StatusFile path\to\docking_results\summary_status.txt
```

失败重试可使用 `-OnlyFailed`、`-OnlyTimeouts` 和 `-RecoveryMode`。重试时建议通过 `-SummaryName` 指定独立的汇总文件，避免覆盖完整的 `summary.csv`；具体见[处理流程](docs/WORKFLOW.md)。

## 本次 SPP1 对接区域

使用成熟 SPP1 的 A 链，以 RGD159–161 附近为功能位点，盒中心为 `(-17.2, -52.6, 19.8)` Å，三个方向的边长均为 30 Å。所有配体使用同一对接区域。

该区域定义用于功能位点附近的探索性对接，不能据此认定存在经过晶体结构验证的小分子结合口袋。详见[区域定义](configs/pocket_definition.txt)及[受体质控记录](docs/receptor_processing_report.txt)。

## 验证范围

整理后的脚本已进行 PowerShell 语法检查及 Python 编译检查。这些检查不等同于重新完成整套配体处理或分子对接；运行前仍需配置依赖和输入文件。

