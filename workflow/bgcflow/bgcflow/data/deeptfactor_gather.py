import json
import logging
import sys
from pathlib import Path

import pandas as pd
from alive_progress import alive_bar

log_format = "%(levelname)-8s %(asctime)s   %(message)s"
date_format = "%d/%m %H:%M:%S"
logging.basicConfig(format=log_format, datefmt=date_format, level=logging.DEBUG)


def combine_deeptfactor_prediction(input_json, filter_str="_deeptfactor"):
    container = {}
    logging.info("Reading json files...")
    with alive_bar(len(input_json), title="Merging DeepTFactor prediction:") as bar:
        for item in input_json:
            item = Path(item)
            genome_id = item.stem
            if filter_str in genome_id:
                genome_id = genome_id.replace(filter_str, "")
            logging.debug(f"Processing {genome_id}")
            with open(item, "r") as f:
                data = json.load(f)
                container.update(data)
            bar()
    return container


def write_deeptf_table(input_json, deeptf_table):
    """
    Write df_deeptfactor.csv table in processed data
    """
    # Handle multiple json
    input_json = Path(input_json)
    logging.info(input_json)
    if input_json.is_file() and input_json.suffix == ".json":
        logging.info(f"Getting deepTFactor overview from a single file: {input_json}")
        input_json_files = input_json

    elif input_json.is_file() and input_json.suffix == ".txt":
        logging.info(f"Getting deepTFactor overview from a text file: {input_json}")
        with open(input_json, "r") as file:
            file_content = [i.strip("\n") for i in file.readlines()]
            if len(file_content) == 1:
                # Paths space-separated on a single line
                paths = file_content[0].split()
            else:
                # Paths written on separate lines
                paths = file_content
            input_json_files = [
                Path(path) for path in paths if Path(path).suffix == ".json"
            ]
    else:
        input_json_files = [
            Path(file)
            for file in str(input_json).split()
            if Path(file).suffix == ".json"
        ]
        logging.info(
            f"Getting deepTFactor overview from the given list of {len(input_json_files)} files..."
        )

    df = combine_deeptfactor_prediction(input_json_files)
    df = pd.DataFrame.from_dict(df).T
    df.index.name = "locus_tag"

    logging.debug(f"Writing file to: {deeptf_table}")

    # Save dataframes to csv tables
    df_table = Path(deeptf_table)
    df_table.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(deeptf_table, index=True)
    logging.info("Job done")
    return None


if __name__ == "__main__":
    write_deeptf_table(sys.argv[1], sys.argv[2])
