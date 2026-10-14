# Install TWRP

These steps are only for the Acer Iconia One 7 B1-780 Wi-Fi (`acer_barricadewifi`). Install Android Platform Tools and charge the tablet before starting.

1. Enable **OEM unlocking** and **USB debugging** in Android.
2. Reboot to the bootloader:

   ```text
   adb reboot bootloader
   ```

3. Unlock the bootloader if it is still locked. This factory-resets the tablet:

   ```text
   fastboot oem unlock
   ```

4. Download `twrp-3.0.2-0-b1-780-bootstrap.img` and `SHA256SUMS.txt` from the latest release. Verify the SHA-256 digest.
5. Flash recovery:

   ```text
   fastboot flash recovery twrp-3.0.2-0-b1-780-bootstrap.img
   ```

6. Use the hardware keys to boot recovery immediately. The stock recovery interface can remain visible for about eight seconds before TWRP opens.

On this bootloader, `fastboot reboot` can report that reboot is unsupported. Hold Power for about 10–15 seconds, then use the recovery key combination.

## Before installing a ROM

In TWRP, create a backup of Boot, System, Data and NVRAM when those partitions are offered. Copy the complete `TWRP/BACKUPS` directory to a computer before wiping anything.
