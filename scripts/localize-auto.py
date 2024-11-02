#!/usr/bin/env python

import json
import os
import sys
from openai import OpenAI


client = OpenAI(
    # This is the default and can be omitted
    api_key=os.environ.get("OPENAI_API_KEY"),
)


def get_text_message(text, language, context=None):
    if context is not None:
        return f"Please translate '{text}' into {language}."
    return f"Please translate {text} into {language} given '{context}' context"


def translate_text(text, language, context=None):
    response = client.chat.completions.create(
        messages=[
            {
                "role": "system",
                "content": "You are a helpful assistant who helps provide translations for developers. You will only return a plain text translation for the given string and no other information or context. Please do not add any quotes around the translated text.",
            },
            {
                "role": "user",
                "content": get_text_message(text, language, context),
            },
        ],
        model="gpt-4",
    )

    return response.choices[0].message.content


def localize_text(seed_file_path, output_file_path):
    # Load the seed file
    with open(seed_file_path, "r", encoding="utf-8") as seed_file:
        data = json.load(seed_file)

    # Ensure the seed file has the required structure
    if "strings" not in data:
        print("Seed file is missing the 'strings' key.")
        return

    # Determine the number of translations for the " " string
    reference_key = " "
    if (
        reference_key not in data["strings"]
        or "localizations" not in data["strings"][reference_key]
    ):
        print(f"Reference key '{reference_key}' is missing from the seed file.")
        return

    reference_translations = data["strings"][reference_key]["localizations"]

    # Collect strings with fewer translations than the reference
    incomplete_translations = {}
    for key, value in data["strings"].items():
        comment = value.get("comment", "")
        incomplete_translations[key] = comment

    # Translate the incomplete translations
    for key in incomplete_translations:
        print(f"Translating '{key}'")
        text = key
        context = incomplete_translations[key]
        data_ref = data["strings"][key]
        if "localizations" not in data_ref:
            data_ref["localizations"] = {}
        print(f"   Reference translations: {data_ref}")
        for language in reference_translations:
            if language in data_ref["localizations"]:
                print(f"   Translation for '{language}' already exists")
                if isinstance(data_ref["localizations"][language], str):
                    print("   Updating translation to new format")
                    data_ref["localizations"][language] = {
                        "stringUnit": {
                            "state": "translated",
                            "value": data_ref["localizations"][language],
                        }
                    }
                continue
            print(f"   Translating into {language}")
            translation = translate_text(text, language, context)
            print(f"   Translated as {translation}")
            data_ref["localizations"][language] = {
                "stringUnit": {"state": "translated", "value": translation}
            }
        print(f"   Updated translations: {data["strings"][key]}")

    # Write the updated translations to the output file
    with open(output_file_path, "w", encoding="utf-8") as output_file:
        json.dump(data, output_file, ensure_ascii=False, indent=4)


if __name__ == "__main__":
    if sys.argv[-1] == "--help":
        print(
            "Usage: python export_incomplete_translations.py <seed_file_path> <output_file_path>"
        )
    else:
        seed_file_path = (
            sys.argv[1] if len(sys.argv) > 1 else "../Shared/Localizable.xcstrings"
        )
        output_file_path = (
            sys.argv[2] if len(sys.argv) > 2 else "../Shared/Localizable.xcstrings"
        )
        localize_text(seed_file_path, output_file_path)
