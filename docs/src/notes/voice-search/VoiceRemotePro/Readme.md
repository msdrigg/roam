## Voice Remote Pro API

### General API

### Next Steps

1.  Go back through all my steps that I did and write them out here

    -   Figure out the WPS key-entry-file information
    -   Figure out how the WPS key of 000000 wasn't really happening -- it is button press interface (triggered by remote pairing flow)
    -   Figure out about roku specific vendor data and how it was required
    -   Figure out about libpcap and how to inject packets at the interface level
    -   Figure out that my problem was not the wps but the AP level encryption
    -   Figure out each unique mac connection got its own unique WPA psk which would make it unsniffable even if I could connect.
    -   Figure out that I could sniff roku WLAN traffic by
        1. Force set the mac address to match the remote's
        2. Connect to the Roku and get a new WPA PSK
        3. Drop connection
        4. Now force set mac address to match the TV's
        5. Simulate a connection WPS +WPA server using wpa_supplicant and some vendor ie data so the roku voice remote connects
        6. When it connects, give it the WPA PSK that we just received from the roku
        7. Quickly, shut ourselves down and turn the TV back on
        8. The remote will re-connect using the PSK we just gave them and it will work b/c the tv already has it set
        9. Traffic is now sniffable
        -   See wps.sh for the server part [4-7]
        -   Need to build a similar .sh command for the client part [1-3]

2.  Get some more captures of the data that gets sent over the voice-command interface and see if I can analyze it somehow

    -   What is the protocol? Does it rely on libsas or are there other markers? Does it use tftp?

3.  Get a dump of the firmware
    -   We already have encrypted over-the-wire firmware dump but it is heavily encrypted. Need to get the unencrypted version possibly off the chip itself
