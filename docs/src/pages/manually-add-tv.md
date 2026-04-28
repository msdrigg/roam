---
hide_table_of_contents: true
---

# Manually Adding a TV

1. Find your TV's IP Address
    - Turn on your TV and navigate to **Settings** > **Network** > **About**
    - If you do not have a physical remote or another way to control the TV, check your home router's admin interface or DHCP client list for the Roku's IP address instead
    - The IP Address should look like 10.x.x.x, 172.x.x.x, 173.x.x.x or 192.168.x.x
    - This page may list a "Gateway" address and an "IP Address". Make sure you are NOT using the "Gateway" address
2. Navigate to Roam settings and click "Add a device manually"
3. Name your device however you want to, and enter the device IP exactly as shown on the Roku TV
4. Click Save. Now your Roku should be able to connect and function normally

## What if you add the TV manually and Roam still can't connect or the connection isn't working properly?

If Roam still can't control your Roku, please try the following steps

-   [WatchOS ONLY]: Please go to **Settings -> System -> Advanced System Settings -> Control by mobile apps** and make sure it is set to **Permissive**
-   Make sure your iOS device is connected to the same WiFi network as your Roku TV
-   Make sure your TV is turned on
-   Make sure Local Network Permissions is enabled for Roam (or disable and re-enable it if it is already enabled)
    -   On macOS: Go to System Settings -> Privacy and Security -> Local Network -> Roam
    -   On iOS: Go to Settings -> Apps -> Roam -> Local Network
-   If the Roku is not connected to WiFi and you do not have a physical remote, follow Roku's mobile app connection steps here: [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)
-   See additional possibilities here [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## What if I have a complicated network/VPN setup? What protocols does this app use?

-   Roam uses several different protocols to communicate with the TV
    -   TCP (HTTP/Websockets) on port 8060 for sending commands to the TV and querying device state
    -   WOL magic packet (UDP multicast to address 255.255.255.255) to wake up the TV from deep sleep
    -   RDP (UDP) on port 6970 for the headphones mode audio stream
-   All Roku TV's use port 8060 and there is no way to change this on the TV side. But if you have some kind of port forwarding setup and want to use a different outgoing port from Roam, it is possible. You just need to enter `[IP]:[Port]` into the "Ip Address" field instead of just `[IP]`. For example, enter `192.168.8.242:8061` and the port `8061` will be used.
