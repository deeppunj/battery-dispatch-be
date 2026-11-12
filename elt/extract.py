# Step 1 of the pipeline: download Elia's total-load data (open data, free).
# Run from the repository root:  python elt/extract.py
# The file is saved with today's date, so each download is kept as it arrived.

from datetime import date
from pathlib import Path

import requests

# Elia open data set: "Measured and forecasted total load on the Belgian grid (Historical data)".
URL = "https://opendata.elia.be/api/explore/v2.1/catalog/datasets/ods001/exports/csv"

# use_labels gives the same column names as the file already in data/;
# the semicolon is the separator used in that file.
PARAMS = {"delimiter": ";", "use_labels": "true"}

# The repository folder is one level above this elt folder (works from the terminal and from PyCharm).
ROOT = Path(__file__).resolve().parent.parent
OUTPUT_FILE = ROOT / "data" / f"elia_total_load_{date.today().isoformat()}.csv"


def main():
    # stream=True so the large file is written to disk piece by piece.
    with requests.get(URL, params=PARAMS, stream=True, timeout=300) as response:
        response.raise_for_status()
        with open(OUTPUT_FILE, "wb") as f:
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                f.write(chunk)
    print(f"Saved {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
