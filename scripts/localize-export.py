import json
import sys

def export_incomplete_translations(seed_file_path, output_file_path):
    # Load the seed file
    with open(seed_file_path, 'r', encoding='utf-8') as seed_file:
        data = json.load(seed_file)

    # Ensure the seed file has the required structure
    if "strings" not in data:
        print("Seed file is missing the 'strings' key.")
        return

    # Determine the number of translations for the " " string
    reference_key = " "
    if reference_key not in data["strings"] or "localizations" not in data["strings"][reference_key]:
        print(f"Reference key '{reference_key}' is missing from the seed file.")
        return

    reference_translations = data["strings"][reference_key]["localizations"]
    reference_translation_count = len(reference_translations)
    print(f"Found {reference_translation_count} translations in the refrence key")

    # Collect strings with fewer translations than the reference
    incomplete_translations = {}
    for key, value in data["strings"].items():
        if "localizations" in value and len(value["localizations"]) >= reference_translation_count:
            continue
        comment = value.get("comment", "")
        incomplete_translations[key] = comment

    # Write the incomplete translations to the output file
    with open(output_file_path, 'w', encoding='utf-8') as output_file:
        json.dump(incomplete_translations, output_file, ensure_ascii=False, indent=4)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python export_incomplete_translations.py <seed_file_path> <output_file_path>")
    else:
        seed_file_path = sys.argv[1]
        output_file_path = sys.argv[2]
        export_incomplete_translations(seed_file_path, output_file_path)
