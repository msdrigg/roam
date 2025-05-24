---
hide_table_of_contents: true
---

# Thêm TV Thủ Công

1. Tìm địa chỉ IP của TV
    - Bật TV và vào **Cài đặt** > **Mạng** > **Giới thiệu**
    - Địa chỉ IP thường có dạng 10.x.x.x, 172.x.x.x, 173.x.x.x hoặc 192.168.x.x
    - Trang này có thể hiển thị cả địa chỉ "Gateway" và "IP Address". Đảm bảo bạn KHÔNG sử dụng địa chỉ "Gateway"
2. Truy cập vào cài đặt Roam và nhấn "Thêm thiết bị thủ công"
3. Đặt tên thiết bị tùy ý và nhập địa chỉ IP chính xác như hiển thị trên Roku TV
4. Nhấn Lưu. Bây giờ Roku của bạn sẽ có thể kết nối và hoạt động bình thường

## Nếu bạn đã thêm TV thủ công mà Roam vẫn không thể kết nối hoặc kết nối không ổn định thì sao?

Nếu Roam vẫn không thể điều khiển Roku của bạn, hãy thử các bước sau:

-   [Chỉ dành cho WatchOS]: Vào **Cài đặt -> Hệ thống -> Cài đặt hệ thống nâng cao -> Điều khiển qua ứng dụng di động** và đảm bảo tùy chọn này được đặt thành **Cho phép**
-   Đảm bảo thiết bị iOS của bạn kết nối cùng mạng WiFi với Roku TV
-   Đảm bảo TV của bạn đang bật
-   Đảm bảo Quyền truy cập Mạng Cục bộ đã được bật cho Roam (hoặc tắt đi và bật lại nếu đã được bật)
    -   Trên macOS: Vào Cài đặt Hệ thống -> Quyền riêng tư & Bảo mật -> Mạng Cục bộ -> Roam
    -   Trên iOS: Vào Cài đặt -> Ứng dụng -> Roam -> Mạng Cục bộ
-   Xem thêm các khả năng khác tại đây [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## Nếu tôi có cấu hình mạng phức tạp/VPN thì sao? Ứng dụng này sử dụng những giao thức nào?

-   Roam sử dụng nhiều giao thức khác nhau để giao tiếp với TV
    -   TCP (HTTP/Websockets) trên cổng 8060 để gửi lệnh đến TV và truy vấn trạng thái thiết bị
    -   Gói ma thuật WOL (UDP multicast đến địa chỉ 255.255.255.255) để đánh thức TV từ chế độ ngủ sâu
    -   RDP (UDP) trên cổng 6970 dùng cho tính năng âm thanh tai nghe
-   Tất cả các TV Roku đều sử dụng cổng 8060 và không thể thay đổi trên TV. Tuy nhiên, nếu bạn thiết lập chuyển tiếp cổng và muốn sử dụng cổng khác từ Roam, bạn có thể làm được. Chỉ cần nhập `[IP]:[Port]` vào trường "Ip Address" thay vì chỉ nhập `[IP]`. Ví dụ, nhập `192.168.8.242:8061` thì cổng `8061` sẽ được sử dụng.