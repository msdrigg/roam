#!/usr/bin/env python

import json
import os
import re
from openai import OpenAI
import argparse
import hashlib


client = OpenAI(
    # This is the default and can be omitted
    api_key=os.environ.get("OPENAI_API_KEY"),
)

skipped_files = ["upcoming-work.md"]


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


def localize_xcstrings_copied(seed_file_path, output_file_path):
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
        print(f"   Updated translations: {data['strings'][key]}")

    # Write the updated translations to the output file
    with open(output_file_path, "w", encoding="utf-8") as output_file:
        json.dump(data, output_file, ensure_ascii=False, indent=4)


def localize_xcstrings(file_path: str):
    localize_xcstrings_copied(file_path, file_path)


def translate_docusaurus_string_obj(string_obj: dict, language: str):
    response = client.chat.completions.create(
        messages=[
            {
                "role": "system",
                "content": "You are a helpful assistant who helps provide translations for developers. You will only return a plain text translation for the given string and no other information or context. Please do not add any quotes around the translated text.",
            },
            {
                "role": "user",
                "content": get_text_message(
                    string_obj["message"], language, string_obj.get("description")
                ),
            },
        ],
        model="gpt-4",
    )

    return {"message": response.choices[0].message.content}


def get_doc_page_message(page: str, language: str):
    return f"Please translate the following page into {language}:\n\n```\n{page}\n```"


def translate_docusaurus_page(page: str, language: str):
    response = client.chat.completions.create(
        messages=[
            {
                "role": "system",
                "content": 'You are a helpful assistant who helps provide translations for developers for mdx files. Mdx files are markdown files that can contain JSX. Please translate the strings as a whole respecting the grammar of the page and trying to preserve the original meaning of the page as well as keeping the jsx formatted correctly. You will only return a translation for the given page and no other information or context. Please do not add any quotes or "```" marks around the translated page. Also please don\'t translate `true/false` or the parameter names within the frontmatter header. Please do not translate any of the slugs or links or any piece of the `import` lines',
            },
            {
                "role": "user",
                "content": get_doc_page_message(page, language),
            },
        ],
        model="gpt-4",
    )

    result = response.choices[0].message.content
    if result.startswith("```\n"):
        result = result[4:]
    if result.endswith("```\n"):
        result = result[:-4]
    elif result.endswith("```"):
        result = result[:-4]
    return result


def translate_docusaurus_strings_file_content(
    existing_data: dict, seed_data: dict, strings_translation: dict, language: str
) -> dict:
    for key in seed_data:
        # Check if key has changed
        translated_hash = strings_translation.get(key)
        current_hash = hashlib.sha256(
            json.dumps(seed_data[key], sort_keys=True, ensure_ascii=False).encode()
        ).hexdigest()

        if translated_hash != current_hash and key in existing_data:
            print(
                f"Key has changed, retranslating {translated_hash} != {current_hash} {strings_translation}"
            )
            del existing_data[key]
        else:
            print("Key has not changed, skipping")

        if key not in existing_data:
            print(f"Translating {key} into {language}")
            existing_data[key] = translate_docusaurus_string_obj(
                seed_data[key], language
            )
            print(f"Translated {key} into {existing_data[key]}")
        else:
            print(f"Skipping {key} as it already exists")

    for key in existing_data:
        if key not in seed_data:
            del existing_data[key]

    return existing_data


def translate_docusaurus_strings_file(
    translation_dir, relative_file_path: str, strings_translation: dict, language: str
):
    with open(
        os.path.join(translation_dir, "en", relative_file_path),
        "r",
        encoding="utf-8",
    ) as file_data:
        seed_data = json.load(file_data)

    print(f"Translating {relative_file_path} into {language}")

    locale_dir = os.path.join(translation_dir, language)
    file_path = os.path.join(locale_dir, relative_file_path)

    parent_dir = os.path.dirname(file_path)
    if not os.path.exists(parent_dir):
        os.makedirs(parent_dir)

    # Create the file if it doesn't exist

    with open(file_path, "a", encoding="utf-8") as file_data:
        pass

    with open(
        os.path.join(locale_dir, relative_file_path),
        "r+",
        encoding="utf-8",
    ) as file_data:
        data = file_data.read()

        existing_navbar = json.loads(data) if data else {}
        new_navbar = translate_docusaurus_strings_file_content(
            existing_navbar, seed_data, strings_translation, language
        )

        file_data.seek(0)
        json.dump(new_navbar, file_data, ensure_ascii=False, indent=4)
        file_data.truncate()


def unify_strings_cache(strings_translation: dict, file_path: str):
    with open(file_path, "r", encoding="utf-8") as file_data:
        data = json.load(file_data)

    for key in data:
        strings_translation[key] = hashlib.sha256(
            json.dumps(data[key], sort_keys=True, ensure_ascii=False).encode()
        ).hexdigest()


def localize_docusaurus(docs_dir: str):
    # Parse the locales: [.*] from the docusaurus config file (.ts)
    docusaurus_config_file = os.path.join(docs_dir, "docusaurus.config.ts")

    with open(docusaurus_config_file, "r", encoding="utf-8") as config_file:
        config_data = config_file.read()

    # Extract the locales from the config file
    locales = re.findall(r"locales: \[(.*?)\]", config_data, re.MULTILINE | re.DOTALL)[
        0
    ].strip()

    if not locales:
        print(
            f"Locales not found in the Docusaurus config file {docusaurus_config_file}"
        )
        return
    else:
        locales = [
            locale.strip().replace('"', "")
            for locale in locales.split(",")
            if locale.strip().replace('"', "") != "en"
        ]
        print(f"Locales found: {locales}")

    file_translate_map = {}

    translation_dir = os.path.join(docs_dir, "i18n")

    with open(
        os.path.join(translation_dir, "file_hashes.json"), "a", encoding="utf-8"
    ) as file_data:
        pass
    with open(
        os.path.join(translation_dir, "file_hashes.json"), "r", encoding="utf-8"
    ) as file_data:
        data = file_data.read()
        file_hash_state = json.loads(data) if data else {}

    # Find all the files in the pages
    pages_dir = os.path.join(docs_dir, "src", "pages")
    for root, _, files in os.walk(pages_dir):
        for file in files:
            if file.endswith(".md") or file.endswith(".mdx"):
                file_path = os.path.join(root, file)
                relative_file_path = os.path.relpath(file_path, pages_dir)
                if relative_file_path in skipped_files:
                    print(f"Skipping {relative_file_path}")
                    continue
                else:
                    print(f"Processing {relative_file_path}")
                with open(file_path, "r", encoding="utf-8") as file_data:
                    data = file_data.read()
                    # Hash the data with sha256
                    hash = hashlib.sha256(data.encode()).hexdigest()
                file_translate_map[file_path] = {
                    "relative_path": os.path.join(
                        "docusaurus-plugin-content-pages", relative_file_path
                    ),
                    "hash": hash,
                }

    with open(
        os.path.join(translation_dir, "strings.json"), "a", encoding="utf-8"
    ) as file_data:
        pass
    with open(
        os.path.join(translation_dir, "strings.json"), "r", encoding="utf-8"
    ) as file_data:
        data = file_data.read()
        strings_translation = json.loads(data) if data else {}

    for localization in locales:
        print(f"Localizing {localization}")

        locale_dir = os.path.join(translation_dir, localization)

        if not os.path.exists(locale_dir):
            os.makedirs(locale_dir)

        # Translate the code strings first
        translate_docusaurus_strings_file(
            translation_dir, "code.json", strings_translation, localization
        )
        translate_docusaurus_strings_file(
            translation_dir,
            os.path.join("docusaurus-theme-classic", "navbar.json"),
            strings_translation,
            localization,
        )
        translate_docusaurus_strings_file(
            translation_dir,
            os.path.join("docusaurus-theme-classic", "footer.json"),
            strings_translation,
            localization,
        )

        next_file_hash_state = file_hash_state.copy()

        # Translate the pages
        for file_path, file_info in file_translate_map.items():
            relative_file_path = file_info["relative_path"]
            file_hash = file_info["hash"]
            with open(file_path, "r", encoding="utf-8") as file_data:
                data = file_data.read()

            full_path = os.path.join(locale_dir, relative_file_path)
            parent_path = os.path.dirname(full_path)
            if not os.path.exists(parent_path):
                os.makedirs(parent_path)
            has_current = os.path.exists(full_path)
            # Create if not exists
            if not has_current:
                with open(
                    full_path,
                    "a",
                    encoding="utf-8",
                ) as file_data:
                    pass

            if file_hash_state.get(relative_file_path) != file_hash or not has_current:
                print(f"Translating page at {relative_file_path}")
                with open(
                    full_path,
                    "w",
                    encoding="utf-8",
                ) as file_data:
                    translated_data = translate_docusaurus_page(data, localization)
                    file_data.write(translated_data)
                    next_file_hash_state[relative_file_path] = file_hash
            else:
                print(f"Skipping page at {relative_file_path} as it is up to date")

    # Persist the file hash state and the strings translation
    with open(
        os.path.join(translation_dir, "file_hashes.json"), "w", encoding="utf-8"
    ) as file_data:
        json.dump(next_file_hash_state, file_data, indent=4, ensure_ascii=False)

    unify_strings_cache(
        strings_translation,
        os.path.join(translation_dir, "en", "docusaurus-theme-classic", "footer.json"),
    )
    unify_strings_cache(
        strings_translation,
        os.path.join(translation_dir, "en", "docusaurus-theme-classic", "navbar.json"),
    )
    unify_strings_cache(
        strings_translation,
        os.path.join(translation_dir, "en", "code.json"),
    )

    with open(
        os.path.join(translation_dir, "strings.json"), "w", encoding="utf-8"
    ) as file_data:
        json.dump(strings_translation, file_data, indent=4, ensure_ascii=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Localize strings\nThis localizes by default:\n\n- Shared/Localizable.xcstrings\n\n- Shared/InfoPlist.xcstrings\n\n- The docs website (docusaurus)"
    )

    parser.add_argument(
        "--docs",
        help="Docs directory to localize",
    )

    parser.add_argument(
        "--xcstrings",
        help="Xcstrings file to localize (instead of the default behavior)",
    )

    parsed = parser.parse_args()

    if not parsed.docs and not parsed.xcstrings:
        localize_xcstrings(os.path.join("Shared", "Localizable.xcstrings"))
        localize_xcstrings(os.path.join("Shared", "InfoPlist.xcstrings"))
        localize_docusaurus("docs")

    if parsed.docs:
        localize_docusaurus(parsed.docs)

    if parsed.xcstrings:
        localize_xcstrings(parsed.xcstrings)
