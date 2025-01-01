---
hide_table_of_contents: true
---

# Thêm TV Một Cách Thủ Công

1. Tìm địa chỉ IP của TV
    - Bật TV và điều hướng đến **Cài đặt** > **Mạng** > **Thông tin**
    - Địa chỉ IP sẽ có dạng như 10.x.x.x, 172.x.x.x, 173.x.x.x hoặc 192.168.x.x
    - Trang này có thể liệt kê một địa chỉ "Gateway" và một "Địa chỉ IP". Hãy chắc chắn bạn KHÔNG đang sử dụng địa chỉ "Gateway"
2. Điều hướng đến cài đặt Roam và nhấp vào "Thêm một thiết bị thủ công"
3. Đặt tên cho thiết bị của bạn như bạn muốn và nhập địa chỉ IP của thiết bị chính xác như được hiển thị trên Roku TV
4. Nhấp vào Lưu (Save). Bây giờ Roku của bạn nên có thể kết nối và hoạt động bình thường

## Nếu bạn thêm TV thủ công và Roam vẫn không thể kết nối?

Nếu Roam vẫn không thể điều khiển Roku của bạn, hãy thử những bước sau

-   Đảm bảo rằng thiết bị iOS của bạn đã kết nối với cùng một mạng WiFi với Roku TV của bạn
-   Đảm bảo rằng TV của bạn đang được bật
-   Đảm bảo Quyền Hạn Mạng Địa Phương (Local Network Permissions) đã được kích hoạt cho Roam (hoặc vô hiệu hóa và kích hoạt lại nếu nó đã được kích hoạt)
    -   Trên macOS: Đi đến Cài đặt Hệ thống -> Quyền riêng tư và An ninh -> Mạng Địa phương -> Roam
    -   Trên iOS: Đi đến Cài đặt -> Ứng dụng -> Roam -> Mạng Địa phương
-   Xem thêm khả năng khác tại đây [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## Nếu tôi có một cấu hình mạng/VPN phức tạp? Ứng dụng này sử dụng giao thức gì?

-   Roam sử dụng hai giao thức khác nhau để giao tiếp với TV
     -   TCP (HTTP/Websockets) trên cổng 8060 để gửi lệnh đến TV
     -   WOL magic packet (UDP multicast đến địa chỉ 255.255.255.255) để đánh thức TV từ trạng thái ngủ sâu
-   Tất cả Roku TV đều sử dụng cổng 8060 và không có cách nào để thay đổi điều này trên phía TV. Nhưng nếu bạn có một loại cấu hình chuyển tiếp cổng và muốn sử dụng một cổng gửi đi khác từ Roam, điều này có thể. Bạn chỉ cần nhập `<IP>:<Port>` vào trường "Địa chỉ IP" thay vì chỉ `<IP>`. Ví dụ: nhập `192.168.8.242:8061` và cổng được chọn sẽ được sử dụng.
