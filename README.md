
<p align="center">
  <img src="images/Cyphorn_Tunnel.png" alt="Cyphorn Tunnel Logo" width="220"/>
</p>



# cyphorn_tunnel
Cyphorn Tunnel binary and manager script (proprietary)

Cyphorn Tunnel is a proprietary encrypted Layer-4 tunnel over UDP, developed by Mohammad Alhummada.

This repository contains only the binary and the manager script. The source code is not published.
Commercial use requires a paid license. For inquiries: cyphorntech@gmail.com


برنامج Cyphorn Tunnel الثنائي وسكربت الإدارة (ملكي)

يُعد Cyphorn Tunnel نفقًا مشفّرًا مخصصًا من الطبقة الرابعة (Layer-4) عبر بروتوكول UDP، قام بتطويره محمد علي الحماده.
يحتوي هذا المستودع فقط على الملف التنفيذي (الثنائي) وسكربت الإدارة، بينما لم يتم نشر الشيفرة المصدرية.

الاستخدام التجاري يتطلب الحصول على ترخيص مدفوع مسبقًا.
للتواصل: cyphorntech@gmail.com

  --------------------------------------------------------------------------------------------------------------------------------------------------


## Install (clone into the expected path)  (استنساخ في المسار المتوقع)

## Requirements  (المتطلبات)
Debian / Ubuntu:
```bash


sudo apt-get update
sudo apt-get install -y libsodium23

sudo git clone https://github.com/malhummada/cyphorn_tunnel.git /usr/local/bin/cyphorn_tunnel

cd /usr/local/bin/cyphorn_tunnel

sudo chmod +x /usr/local/bin/cyphorn_tunnel/build/cyphorn  /usr/local/bin/cyphorn_tunnel/cyphornctl.sh
```
-------------------------------------------------------------------------
**Usage :    الاستخدام**
**start|stop|restart|status|logs**





-------------------------------------------------------------------------
Examples:  (أمثلة)
-------------------------------------------------------------------------
**Server**: 
```bash
sudo -n /usr/local/bin/cyphorn_tunnel/cyphornctl.sh <start|stop|restart> --role 'server' --dev 'cytun0' --port '60000' --daemon --use-local-bin --tun '10.10.10.1/24' --debug
```



**Get public key by this cmd:**
```bash
sudo -n /usr/local/bin/cyphorn_tunnel/cyphornctl.sh pubkey --role server
```
**status**  **حالة السيرفر**
```bash
sudo -n /usr/local/bin/cyphorn_tunnel/cyphornctl.sh status   --role server
```

**Logs:**  **سجلات الاتصال**
```bash
sudo -n /usr/local/bin/cyphorn_tunnel/cyphornctl.sh logs --role server
```
-------------------------------------------------------------------------
**Client**:
```bash
sudo /usr/local/bin/cyphorn_tunnel/cyphornctl.sh <start|stop|restart> --role client --dev cytun0 --port 60000 --server-ip 192.168.77.1 --peer-pubkey <SERVER_PUBLIC_KEY_HERE> --tun-ptp 10.10.10.3,10.10.10.1 --mtu 1420   --reconnect-min 2 --reconnect-max 10 --debug
```
**status**  **حالة المضيف**
```bash
sudo -n /usr/local/bin/cyphorn_tunnel/cyphornctl.sh status --role client
```
**Logs:**  **سجلات الاتصال**
```bash
sudo -n /usr/local/bin/cyphorn_tunnel/cyphornctl.sh logs --role client
```
--------------------------------------------------------------------------------------------------------------------------------------------------
## License
Cyphorn Tunnel is proprietary software.  
Commercial use requires a paid license.  
⚠️ Unauthorized use, distribution, or modification is strictly prohibited.

Copyright (c) 2025 Mohammad Ali Alhummada.  
Contact: cyphorntech@gmail.com

--------------------------------------------------------------------------------------------------------------------------------------------------
