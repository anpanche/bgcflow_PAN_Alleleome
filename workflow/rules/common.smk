import os
import numpy as np
import pandas as pd
import yaml, json, sys, itertools
from snakemake.utils import validate
from snakemake.utils import min_version

min_version("6.15.1")
__version__ = "0.1.0"


##### TABLE OF CONTENTS #####
# This .smk file helps the rules interact with the user config and contains 
# many helper scripts. The structure can be divided into these sections:
#   1. Load config
#   2. Extract project information
#   3. Generate wildcard constants
#   4. Wildcard constraints
#   5. Helper lambda functions for rules I/O
#   6. Get dependency versions
#   7. Customize final output based on config["rule"] values
#   8. Set up custom resource directory provided in config["resources_path"] 


##### 1. Load config #####
configfile: "config/config.yaml"
validate(config, schema="../schemas/config.schema.yaml")


##### 2. Extract project information #####
def extract_project_information():
    """
    Wrapper to extract variables from projects in config.yaml.
    Under development to accomodate multiple projects running in one snakemake run.
    """
    class ConfigError(Exception):
        """Raised when config.yaml does not satisty requirements"""
        pass

    def merge_nested_list(nested_list):
        """Merge nested list or dict values / keys"""
        return list(itertools.chain(*nested_list))
    
    # load information from config
    projects = pd.DataFrame(config["projects"]).set_index('name', drop=False)
    
    # check validity of {sample}.csv Value should be unique
    check_duplicates = projects[projects.samples.duplicated()]
    if len(check_duplicates) > 0:
        raise ConfigError(f"Project: {check_duplicates.name.to_list()} \
                            input file name: {check_duplicates.samples.to_list()} \
                            is not unique. Check your config.yaml configuration.")

    samples = []
    for i in projects.index:
        df1 = pd.read_csv(projects.loc[i, "samples"])
        df1["sample_paths"] = projects.loc[i, "samples"]

        # try to fetch user-provided custom reference for prokka
        try:
            df1["prokka-db"] = projects.loc[i, "prokka-db"]
        except KeyError:
            df1["prokka-db"] = np.nan
            pass

        # try to fetch user-defined gtdb classification
        try:
            df1["gtdb_paths"] = projects.loc[i, "gtdb-tax"]
        except KeyError:
            df1["gtdb_paths"] = np.nan
            pass

        df1["name"] = projects.loc[i, "name"]
        df1 = df1.set_index('genome_id', drop=False)
        samples.append(df1)
    df_samples = pd.concat(samples, axis=0)
    validate(df_samples.fillna(""), schema="../schemas/samples.schema.yaml")

    # check validity of genome_ids. Value should be unique.
    check_duplicates = df_samples[df_samples.genome_id.duplicated()]
    if len(check_duplicates) > 0:
        raise ConfigError(f"Strain ids in: {check_duplicates.sample_paths.to_list()} \
                            are not unique. Check your config.yaml configuration.")

    prokka_db = []
    for i in projects.index:
        try:
            df2 = pd.read_csv(projects.loc[i, "prokka-db"])
            df2["name"] = projects.loc[i, "name"]
            df2 = df2.set_index('Accession', drop=False)
            prokka_db.append(df2)
            df_prokka_db = pd.concat(prokka_db, axis=0).reset_index(drop=True)
        except (ValueError, KeyError) as e:
            df_prokka_db = pd.DataFrame(columns=["Accession", "name"])
            pass
    
    return projects, df_samples, df_prokka_db

DF_PROJECTS, DF_SAMPLES, DF_PROKKA_DB = extract_project_information()


##### 3. Generate wildcard constants #####
PROJECT_IDS = DF_SAMPLES.name.unique()
STRAINS = DF_SAMPLES.genome_id.to_list()
CUSTOM = DF_SAMPLES[DF_SAMPLES.source.eq("custom")].genome_id.to_list()
NCBI = DF_SAMPLES[DF_SAMPLES.source.eq("ncbi")].genome_id.to_list()
PATRIC = DF_SAMPLES[DF_SAMPLES.source.eq("patric")].genome_id.to_list()
PROKKA_DB = DF_PROKKA_DB.Accession.to_list()
SAMPLE_PATHS = list(DF_SAMPLES.sample_paths.unique())
GTDB_PATHS = list(DF_SAMPLES.gtdb_paths.unique())


##### 4. Wildcard constraints #####
wildcard_constraints:
    strains="|".join(STRAINS),
    ncbi="|".join(NCBI),
    custom="|".join(CUSTOM),
    patric="|".join(PATRIC),
    name="|".join(PROJECT_IDS),


##### 5. Helper lambda functions for calling rules I/O #####

# seqfu.smk #
def get_fasta_inputs(name, df_samples=DF_SAMPLES):
    """
    Given a project name, list all corresponding strains (genome_id)
    """
    selection = df_samples[df_samples["name"] == name].genome_id.values
    output = [f"data/interim/fasta/{s}.fna" for s in selection]
    return output

# prokka.smk #
def get_prokka_refdb(genome_id, params, df_samples=DF_SAMPLES):
    """
    Given a genome id, find which prokka-db input to use.
    params:
        - "table" - will return the corresponding prokka-db table to use
        - "file" - will return the corresponding reference gbks
        - "params" - will return prokka protein params and the corresponding file
    """
    prokka_db = df_samples.loc[genome_id, "prokka-db"][0]
    name = df_samples.loc[genome_id, "name"][0]
    if not os.path.isfile(str(prokka_db)):
        if params == "file":
            output = []
        else:
            output = ""
    elif params == "table":
        output = prokka_db
    elif params == "file":
        output = f"resources/prokka_db/reference_{name}.gbff"
    elif params == "params":
        output = f"--proteins resources/prokka_db/reference_{name}.gbff"
    else:
        sys.stderr.write(f"Second argument should be: table, file, or params.\n")
        raise
    return output

# bigscape.smk, bigslice.smk, and bgc_analytics.smk #
def get_antismash_inputs(name, version, df_samples=DF_SAMPLES):
    """
    Given a project name, find the corresponding sample file to use
    """
    selection = df_samples[df_samples["name"] == name].genome_id.values
    output = [f"data/interim/antismash/{version}/{s}/{s}.gbk" for s in selection]
    return output

# roary.smk #
def get_roary_inputs(name, df_samples=DF_SAMPLES):
    """
    Given a project name, find the corresponding sample file to use
    """
    selection = df_samples[df_samples["name"] == name].genome_id.values
    output = [f"data/interim/prokka/{s}/{s}.gff" for s in selection]
    return output

# automlst_wrapper.smk #
def get_automlst_inputs(name, df_samples=DF_SAMPLES):
    """
    Given a project name, find the corresponding sample file to use
    """
    selection = df_samples[df_samples["name"] == name].genome_id.values
    output = [f"data/interim/automlst_wrapper/{name}/{s}.gbk" for s in selection]
    return output

# gtdb.smk #
def get_json_inputs(name, df_samples=DF_SAMPLES):
    """
    Given a project name, find the corresponding sample file to use
    """
    selection = df_samples[df_samples["name"] == name].genome_id.values
    output = [f"data/interim/gtdb/{s}.json" for s in selection]
    return output

# ncbi.smk #
def get_ncbi_assembly_inputs(name, df_samples=DF_SAMPLES):
    """
    Given a project name, find the corresponding sample file to use
    """
    selection = df_samples[df_samples["name"] == name].genome_id.values
    selection_ncbi = df_samples[df_samples["source"] == "ncbi"].genome_id.values
    output = [f"data/interim/assembly_report/{s}.json" for s in selection_ncbi]
    return output

##### 6. Get dependency versions #####
def get_dependency_version(dep, dep_key):
    """
    return dependency version tags given a dictionary (dep) and its key (dep_key)
    """
    with open(dep[dep_key]) as file:
        result = []
        documents = yaml.full_load(file)
        for i in documents["dependencies"]:
            if i.startswith(dep_key):
                result = i.split("=")[-1]
    return str(result)

def get_dependencies(dep):
    """
    get dependency version
    """
    dv = {}
    for ky in dep.keys():
        vr = get_dependency_version(dep, ky)
        dv[ky] = vr
    return dv


# list of the main dependecies used in the workflow
dependencies = {"antismash" : r"workflow/envs/antismash.yaml",
                "prokka": r"workflow/envs/prokka.yaml",
                "mlst" : r"workflow/envs/mlst.yaml",
                "eggnog-mapper" : r"workflow/envs/eggnog.yaml",
                "roary" : r"workflow/envs/roary.yaml",
                "refseq_masher" : r"workflow/envs/refseq_masher.yaml",
                "seqfu" : r"workflow/envs/seqfu.yaml",
                'checkm' : r"workflow/envs/checkm.yaml",
                }

dependency_version = get_dependencies(dependencies)


##### 7. Customize final output based on config["rule"] values #####
def get_final_output():
    """
    Generate final output for rule all given a TRUE value in config["rules"]
    """
    # dictionary of rules and its output files
    rule_dict = {"mlst" : expand("data/interim/mlst/{strains}_ST.csv", strains = STRAINS),
                "eggnog" : expand("data/interim/eggnog/{strains}/", strains = STRAINS),
                "refseq_masher" : expand("data/interim/refseq_masher/{strains}_masher.csv", \
                                         strains = STRAINS),
                "automlst_wrapper" : expand("data/processed/{name}/automlst_wrapper/{name}.newick", \
                                            name=PROJECT_IDS),
                "roary" : expand("data/processed/{name}/roary/gene_presence_absence.csv", name=PROJECT_IDS),
                "bigscape" : expand("data/processed/{name}/bigscape/{name}_bigscape_as{version}.zip", \
                                    version=dependency_version["antismash"], name=PROJECT_IDS),
                "seqfu" : expand("data/processed/{name}/tables/df_seqfu_stats.csv", name=PROJECT_IDS),
                "rnammer": "resources/rnammer_test.txt",
                "bigslice": expand("data/interim/bigslice/{name}_antismash_{version}/", \
                                    name = PROJECT_IDS, version=dependency_version["antismash"]),
                "query_bigslice": expand("data/interim/bigslice/query/{name}_antismash_{version}/", \
                                         name = PROJECT_IDS, version=dependency_version["antismash"]),
                "checkm" : expand("data/interim/checkm/json/{strains}.json", strains=STRAINS),
                "prokka-gbk" : [f"data/processed/{DF_SAMPLES.loc[strains, 'name']}/genbank/{strains}.gbk" for strains in STRAINS],
                "antismash-summary": expand("data/processed/{name}/tables/df_antismash_{version}_summary.csv", \
                                            name = PROJECT_IDS, version=dependency_version["antismash"]),
                "antismash-zip": [f"data/processed/{DF_SAMPLES.loc[strains, 'name']}/antismash/{dependency_version['antismash']}/{strains}.zip" for strains in STRAINS],
                "arts": expand("data/interim/arts/antismash-{version}/{strains}/", \
                                version=dependency_version["antismash"], strains = STRAINS)
                }
    
    # get keys from config
    opt_rules = config["rules"].keys()

    # if values are TRUE add output files to rule all
    final_output = [rule_dict[r] for r in opt_rules if config["rules"][r]]

    if NCBI == []:
        pass
    else:
        final_output.extend(expand("data/processed/{name}/tables/df_ncbi_meta.csv", name = PROJECT_IDS))
     
    return final_output


##### 8. Set up custom resource directory provided in config["resources_path"] #####
def custom_resource_dir():
    """
    Generate symlink for user defined resources location
    """
    resource_dbs = config["resources_path"]
    sys.stderr.write(f"Checking for user-defined local resources...\n")
    for r in resource_dbs.keys():
        # check for default path
        path = Path(resource_dbs[r])
        if resource_dbs[r] == f"resources/{r}":
            pass 
        # check for user-defined external resources
        elif path.exists():
            try:    
                slink = Path(f"resources/{r}")
                existing_path = Path.readlink(slink)
                # check if symlink for extrenal path is already generated
                if existing_path == path:
                    sys.stderr.write(f"- Symlink for {r} already exists at: {existing_path}\n")
                # update symlink because new path is given
                else:
                    slink.unlink()
                    slink.symlink_to( path )
                    updated_path = Path.readlink(Path(slink)) 
                    sys.stderr.write(f"- Updating symlink for {r} from: {existing_path} to: {updated_path}\n")
            # generate a new symlink
            except FileNotFoundError:
                sys.stderr.write(f"- Generating symlink for {r} from: {path}\n")                    
                slink.symlink_to( path )
        # raise an Error if external path not found
        else:
            raise FileNotFoundError(f"Error: User-defined resource {r} at {path} does not exist. \
                                    Check the config.yaml and provide the right path for resource {r} \
                                    or change it to the default path: resources/{r}\n")
    return 

custom_resource_dir()