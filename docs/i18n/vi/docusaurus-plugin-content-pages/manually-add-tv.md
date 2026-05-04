---
hide_table_of_contents: true
---

# Thêm TV Thủ Công

1. Tìm địa chỉ IP của TV của bạn
    - Bật TV và vào **Cài đặt** > **Mạng** > **Giới thiệu**
    - Nếu bạn không có điều khiển vật lý hoặc không có cách nào khác để điều khiển TV, hãy kiểm tra giao diện quản trị của router tại nhà bạn hoặc danh sách máy khách DHCP để tìm địa chỉ IP của Roku
    - Địa chỉ IP nên có dạng 10.x.x.x, 172.x.x.x, 173.x.x.x hoặc 192.168.x.x
    - Trang này có thể liệt kê một địa chỉ "Gateway" và một "Địa chỉ IP". Hãy chắc chắn rằng bạn KHÔNG sử dụng địa chỉ "Gateway"
2. Truy cập vào cài đặt Roam và nhấn "Thêm thiết bị thủ công"
3. Đặt tên cho thiết bị theo ý muốn của bạn, và nhập chính xác địa chỉ IP thiết bị như hiển thị trên Roku TV
4. Nhấn Lưu. Bây giờ Roku của bạn sẽ có thể kết nối và hoạt động bình thường

## Nếu bạn thêm TV thủ công mà Roam vẫn không kết nối được hoặc kết nối không hoạt động đúng thì sao?

Nếu Roam vẫn không thể điều khiển Roku của bạn, vui lòng thử các bước sau

-   [Chỉ watchOS]: Vào **Cài đặt -> Hệ thống -> Cài đặt nâng cao hệ thống -> Điều khiển bằng ứng dụng di động** và đảm bảo được đặt là **Cho phép**
-   Đảm bảo thiết bị iOS của bạn kết nối cùng mạng WiFi với Roku TV
-   Đảm bảo TV đang được bật
-   Đảm bảo Quyền Truy cập Mạng Cục Bộ đã được cấp cho Roam (hoặc tắt đi và bật lại nếu đã bật)
    -   Trên macOS: Vào Cài đặt Hệ thống -> Quyền riêng tư và Bảo mật -> Mạng cục bộ -> Roam
    -   Trên iOS: Vào Cài đặt -> Ứng dụng -> Roam -> Mạng cục bộ
-   Nếu cấu hình mạng gia đình đã thay đổi khiến thiết bị từng hoạt động bị dừng, hãy xóa thiết bị đó khỏi Roam và quét lại
-   Nếu Roku không kết nối WiFi và bạn không có điều khiển vật lý, làm theo hướng dẫn kết nối ứng dụng di động Roku tại đây: [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)
-   Xem thêm các khả năng khác tại đây [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## Nếu tôi có một hệ thống mạng/VPN phức tạp thì sao? Ứng dụng này sử dụng những giao thức nào?

-   Roam sử dụng một số giao thức khác nhau để giao tiếp với TV
    -   TCP (HTTP/Websockets) trên cổng 8060 để gửi lệnh tới TV và truy vấn trạng thái thiết bị
    -   Gói ma thuật WOL (UDP multicast tới địa chỉ 255.255.255.255) để đánh thức TV từ trạng thái ngủ sâu
    -   RDP (UDP) trên cổng 6970 cho âm thanh chế độ tai nghe
-   Tất cả Roku TV đều sử dụng cổng 8060 và không có cách thay đổi cổng này từ phía TV. Tuy nhiên, nếu bạn thiết lập chuyển tiếp cổng và muốn sử dụng cổng ra khác từ Roam, bạn có thể. Chỉ cần nhập `[IP]:[Port]` vào trường "Địa chỉ IP" thay vì chỉ nhập `[IP]`. Ví dụ, nhập `192.168.8.242:8061` thì cổng `8061` sẽ được sử dụng.