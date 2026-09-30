from MolKit import Read
from AutoDockTools.MoleculePreparation import AD4ReceptorPreparation
import sys

input_file = sys.argv[1]
output_file = sys.argv[2]
mols = Read(input_file)
if not mols:
    raise RuntimeError("No molecule read")
mol = mols[0]
mol.buildBondsByDistance()
AD4ReceptorPreparation(
    mol,
    mode='automatic',
    repairs='bonds_hydrogens',
    charges_to_add='Kollman',
    cleanup='nphs_lps_waters_nonstdres',
    outputfilename=output_file,
    delete_single_nonstd_residues=False,
)
print("prepared receptor: %s" % output_file)


