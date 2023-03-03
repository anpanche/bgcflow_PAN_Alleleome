import logging
import sys
from pathlib import Path

from Bio import SeqIO

log_format = "%(levelname)-8s %(asctime)s   %(message)s"
date_format = "%d/%m %H:%M:%S"
logging.basicConfig(format=log_format, datefmt=date_format, level=logging.DEBUG)


def gbk_to_faa(input_files, output_file):
    output = []
    for i in input_files.split():
        input_file = Path(i).resolve()
        with open(input_file.resolve()) as handle:
            for record in SeqIO.parse(handle, "genbank"):
                logging.info(f"Processing file: {input_file}")
                for seq_feature in record.features:
                    if seq_feature.type == "CDS":
                        assert len(seq_feature.qualifiers["translation"]) == 1
                        text = ">%s from %s\n%s\n" % (
                            seq_feature.qualifiers["locus_tag"][0],
                            record.name,
                            seq_feature.qualifiers["translation"][0],
                        )
                        output.append(text)
    with open(output_file, "w") as f:
        for item in output:
            f.write(item)
    return


if __name__ == "__main__":
    gbk_to_faa(sys.argv[1], sys.argv[2])
