---
hide_table_of_contents: true
---

# Lộ Trình Roam

## Công Việc Đã Hoàn Thành cho Bản Cập Nhật Tiếp Theo

- Thêm các widget điều khiển: Phát, Tắt tiếng, Thay đổi âm lượng và Chọn từ Trung tâm điều khiển!
- Cải thiện xử lý trường văn bản cho nhiều ứng dụng roku 
    - Tự động mở trường text khi có chế độ chỉnh sửa text
    - Sao chép, Cắt, Dán từ macOS
    - Sao chép, Cắt, Dán + Chỉnh sửa tổng quát trên iOS
- Báo cáo tốt hơn về quyền truy cập và kết nối mạng cục bộ
- Cải thiện ổn định kết nối

## Sắp Ra Mắt

-   Đang Tiếp Diễn
    -   Đảm bảo việc nhập văn bản trên iOS không bị cắt bên dưới bàn phím (như hiện tại)
    -   Sửa các widget macOS
    -   Đưa phiên bản iOS ra mắt trên app store
        - Đợi phản hồi về việc kháng cáo
    -   Thực hiện kiểm tra tốt hơn trên iOS và macOS để kiểm tra xem hệ thống có kết nối lại và duy trì kết nối trong các trường hợp sau đây không
        - Sau khi đợi một thời gian dài
        - Khi quay lại từ nền
        - Khi khởi động TV từ trạng thái TẮT
        - Khi kết nối lại với internet
        - Khi chuyển thiết bị

-   Tiếp theo: Thêm hẹn giờ tắt tiếng +30 giây với bộ đếm ngược
    -   Giữ mute để tắt tiếng trong +30 giây
    -   Nhấn lại để hủy tắt tiếng và hủy bỏ điều này
    -   Hiển thị một chỉ báo dưới dòng nút tắt tiếng 
        -   Thanh tiến trình có chỉ báo tiến trình tuyến tính
        -   Thanh tiến trình có hai nút: +30 giây, hủy bỏ
        -   Hiển thị dưới bảng nút chính để dễ dàng tiếp cận với nút tắt tiếng
    -   Cấu hình +30 thành các tùy chọn tắt tiếng 30, 15, 60 giây

-   Tương lai: Cung cấp một giao diện Minimalist tùy chọn trên iOS mô phỏng gần như remote của siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Hỗ trợ cả cử chỉ của visionos...

## Ý Tưởng Tương Lai Chung

-   Viết một bài viết blog về bot discord và trỏ đến MessageView của tôi
    - Tạo MessageView được tự chứa hơn
-   Viết bài blog về dịch tự động và logic xung quanh nó
-   Viết bài blog về NWConnection so với URLSession cho websockets
-   Viết một bài viết blog về phím tắt bàn phím tùy chỉnh
-   Viết bài viết blog về ECP Textedit API
-   Viết bài viết blog về widget trung tâm điều khiển

-   Tạo biểu tượng thanh menu tùy chỉnh

-   Làm thế nào để sử dụng văn bản-để-văn bản hoặc các lệnh giọng nói thông thường?
    - Cần đảo ngược giao thức udp của remote giọng nói roku
    - Hoặc cần thêm văn bản tùy chỉnh-để-phát biểu với máy chủ nút từ xa?

-   Tự động Chụp Ảnh Màn hình

    -   Sử dụng UITests để lấy ảnh chụp màn hình thực tế cho tất cả các kích thước thiết bị + địa phương
    -   Sử dụng AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w để lấy ảnh chụp màn hình trong các khung
    -   Hoặc một cái gì đó khác
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Thử nghiệm thêm cho bàn phím iPad
    -   GCKeyboard cho một
    -   FocusEnvironment cho 2
    -   Đảm bảo rằng giải pháp được sử dụng cho iOS không làm hỏng việc nhập văn bản trong thông điệp/đầu vào bàn phím

-   UI Tests
    -   Kiểm tra khi thiết bị được thêm vào thì nó xuất hiện tại chọn thiết bị và được chọn bởi roam
    -   Kiểm tra xem người dùng có thể điều hướng tới thiết lập -> thiết bị không
    -   Kiểm tra xem người dùng có thể điều hướng tới thiết lập -> tin nhắn không
    -   Kiểm tra xem người dùng có thể điều hướng tới thiết lập -> về không
    -   Kiểm tra xem người dùng có thể chỉnh sửa/xóa thiết bị không
    -   Kiểm tra xem người dùng có thể bấm nút sau khi thêm thiết bị không
    -   Kiểm tra xem người dùng có thể thấy biểu ngữ không có thiết bị khi nó xuất hiện không
    -   Kiểm tra xem người dùng có thấy applinks không
    -   Tham khảo modelcontainers của swiftdat testingmodelcontainer
    -   Tham khảo tại đây https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad để cài đặt kiểm tra

## Sửa Lỗi

-   Tìm hiểu xem vòng lặp các cuộc gọi tới `nextPacket` có hợp lý không.
    -   Thay vì lập mỗi 10ms và hy vọng việc tính thời gian là đúng, liệu tôi có nên lập qua các gói đã nhận và cố gắng lịch chúng tại thời gian máy chủ `10ms * globalSequenceNumber + startHostTime` và thời gian mẫu tại `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime` không
    -   Sau đó tôi có thể chuyển từ vòng lặp `for await` qua đồng hồ sang một vòng lặp `while !Task.isCancelled` với `Task.sleep` ở trong nó.
    -   Okay vậy chúng ta cần lập mỗi 10 ms và cố gắng kéo gói cuối cùng ra sau đó lịch nó tại thời điểm đó
    -   Mỗi khi chúng tôi thực hiện đồng bộ audio
        -   Chúng tôi có lastRenderTime + gói đồng bộ
        -   Ước tính số gói chúng tôi nên gửi đi tại + thời gian đồng bộ
            -   Thời gian hiển thị + bổ sung

## Cải Thiện Thông Điệp Người Dùng Quanh Quản Lý Thông Tin/Tình Trạng/Khả Năng 

-   Khi bật thiết bị với WOL và không kết nối sau 5 giây, hoặc khi khởi động thiết bị và ngay lập tức thất bại, hiển thị tin nhắn cảnh báo dưới wifi
    -   “Chúng tôi không thể đánh thức Roku của bạn” (Tìm hiểu thêm) (Không hiển thị lại cho thiết bị này), (X)
    -   Tìm hiểu thêm hiển thị một số lý do tại sao
        -   Bạn không kết nối cùng một mạng (Hiển thị tên mạng thiết bị cuối cùng. Hỏi xem người dùng có đang kết nối với mạng này không)
        -   Thiết bị của bạn đang trong trạng thái chờ sâu (không được tắt gần đây) và không thể được đánh thức
            -   Thiết bị của bạn không hỗ trợ WWOL và kết nối với wifi
            -   Thiết bị của bạn không hỗ trợ WWOL hoặc WOL
        -   Mạng của bạn không được thiết lập để cho phép chúng tôi gửi lệnh đánh thức tới thiết bị
-   Khi nhấp vào một nút đã tắt, hiển thị thông báo cho biết vì sao nó bị tắt
    -   Hiển thị chỉ số thông tin trên nút để chỉ ra rằng thông tin có thể được nhận khi nó được nhấp?
    -   Chế độ Tai nghe đã được tắt -> vì thiết bị không hỗ trợ chế độ tai nghe để ứng dụng này
    -   Kiểm soát âm lượng đã tắt -> vì âm thanh đang xuất qua HDMI không hỗ trợ kiểm soát âm lượng?
-   Khi đang quét chủ động thiết bị và không tìm thấy thiết bị mới nào, hiển thị một tin nhắn cảnh báo dưới danh sách thiết bị
    -   "Chúng tôi không thể đánh thức Roku của bạn" (Tìm ra vì sao), (X)
    -   Find out more hiển thị một cửa sổ popup với một số lý do tại sao điều này có thể xảy ra
        -   Đảm bảo rằng thiết bị của bạn đang được bật và kết nối với mạng wifi giống như ứng dụng của bạn. Nếu việc này vẫn không hoạt động, hãy thử thêm thiết bị một cách thủ công.
        -   Liên kết https://roam.msd3.io/manually-add-tv.md và https://support.roku.com/article/115001480188 để giải quyết sự cố hoặc trò chuyện thêm
-   Thêm huy hiệu cho supportsWakeOnWLAN và supportsMute

## Để cập nhật khi ngừng hỗ trợ iOS 17/macOS 14 (Tháng 2 2026)

-   Đi xung quanh và xóa các thẻ @available(iOS 18)
-   Sử dụng tính năng xem trước để tiêm dữ liệu mẫu vào các bản xem trước
-   SwiftData
    -   Sử dụng #Index macro mới cho các mô hình
    -   Sử dụng #Unique macro mới cho các mô hình
    -   Sử dụng xóa theo lô
-   TipKit
    -   Sử dụng CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
