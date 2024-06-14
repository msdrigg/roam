import os
import json
import sys

def merge_localizations(directory_path, seed_file_path, output_file_path):
    # Load the seed file
    with open(seed_file_path, "r", encoding="utf-8") as seed_file:
        merged_data = json.load(seed_file)

    # Ensure the seed file has the required structure
    if "strings" not in merged_data:
        print("Seed file is missing the 'strings' key.")
        return

    # Process each localization file in the directory
    for filename in os.listdir(directory_path):
        if filename.endswith(".json") and filename != os.path.basename(seed_file_path):
            lang_code = filename.split(".")[0]
            with open(
                os.path.join(directory_path, filename), "r", encoding="utf-8"
            ) as lang_file:
                lang_data = json.load(lang_file)
                for key, value in lang_data.items():
                    if key not in merged_data["strings"]:
                        continue
                    if "localizations" not in merged_data["strings"][key]:
                        merged_data["strings"][key]["localizations"] = {}
                    merged_data["strings"][key]["localizations"][lang_code] = {
                        "stringUnit": {"state": "translated", "value": value}
                    }

    # Write the merged data to the output file
    with open(output_file_path, "w", encoding="utf-8") as output_file:
        json.dump(merged_data, output_file, ensure_ascii=False, indent=4)

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(
            "Usage: python merge_localizations.py <directory_path> <seed_file_path> <output_file_path>"
        )
    else:
        directory_path = sys.argv[1]
        seed_file_path = sys.argv[2]
        output_file_path = sys.argv[3]
        merge_localizations(directory_path, seed_file_path, output_file_path)
