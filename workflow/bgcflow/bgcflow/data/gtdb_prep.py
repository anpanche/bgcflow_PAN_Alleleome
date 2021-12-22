import os
import sys
import pandas as pd

def gtdb_prep(samples_path, outfile):
    # wrap single or multiple inputs & generate dataframe
    shell_input = samples_path.split()
    dfList = [pd.read_csv(s).set_index('genome_id', drop=False) for s in shell_input]
    df_samples = pd.concat(dfList, axis=0)

    # NCBI accession or closest NCBI
    custom_placement = df_samples[df_samples.source.eq("custom")].closest_placement_reference.tolist()
    ncbi_placement = df_samples[df_samples.source.eq("ncbi")].genome_id.tolist()
    patric_placement = df_samples[df_samples.source.eq("patric")].closest_placement_reference.tolist()
    placement_tax = custom_placement + ncbi_placement + patric_placement

    with open(outfile, "w") as out:
        for acc in placement_tax:
            out.write(acc + "\n")
        out.close()    
    return None

if __name__ == "__main__":
    gtdb_prep(sys.argv[1], sys.argv[2])