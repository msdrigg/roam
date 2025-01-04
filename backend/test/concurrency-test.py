import os
import threading
import json
import http.client


def load_env_file(file_path):
    with open(file_path, "r") as file:
        for line in file:
            # Strip whitespace and ignore comments or blank lines
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            # Split the key-value pair
            key, value = line.split("=", 1)
            os.environ[key.strip()] = value.strip()


def send_request(content, url, api_key, user_id):
    if not url or not api_key:
        print(
            "Please set the BACKEND_URL and API_KEY environment variables before running"
        )
    path = "/new-message"
    headers = {
        "X-API-KEY": api_key,
        "ContentType": "application/json",
    }
    data = json.dumps({"userId": user_id, "apnsToken": None, "content": content})

    conn = http.client.HTTPSConnection(url)
    conn.request("POST", path, body=data, headers=headers)
    response = conn.getresponse()
    print(f"Response for {content}: {response.status}, {response.read().decode()}")
    conn.close()


def main():

    # Load the .env file
    load_env_file(".dev.vars")

    url = os.environ.get("BACKEND_URL", None)
    api_key = os.environ.get("API_KEY", None)
    user_id = "abc-tet-124"

    # Create threads
    thread1 = threading.Thread(
        target=send_request, args=("message1", url, api_key, user_id)
    )
    thread2 = threading.Thread(
        target=send_request, args=("message2", url, api_key, user_id)
    )
    thread3 = threading.Thread(
        target=send_request, args=("message3", url, api_key, user_id)
    )
    thread4 = threading.Thread(
        target=send_request, args=("message4", url, api_key, user_id)
    )
    thread5 = threading.Thread(
        target=send_request, args=("message5", url, api_key, user_id)
    )
    thread6 = threading.Thread(
        target=send_request, args=("message6", url, api_key, user_id)
    )
    thread7 = threading.Thread(
        target=send_request, args=("message7", url, api_key, user_id)
    )
    thread8 = threading.Thread(
        target=send_request, args=("message8", url, api_key, user_id)
    )

    # Start threads
    thread1.start()
    thread2.start()
    thread3.start()
    thread4.start()
    thread5.start()
    thread6.start()
    thread7.start()
    thread8.start()

    # Wait for threads to finish
    thread1.join()
    thread2.join()
    thread3.join()
    thread4.join()
    thread5.join()
    thread6.join()
    thread7.join()
    thread8.join()


if __name__ == "__main__":
    main()
