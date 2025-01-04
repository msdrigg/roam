---
hide_table_of_contents: true
---

# Lộ trình Roam

## Công việc hoàn thành cho Bản cập nhật tiếp theo

-   Thêm các widget điều khiển: Chạy, Tắt tiếng, Thay đổi âm lượng và Chọn từ Trung tâm điều khiển!
-   Thêm cải tiến cho các trường văn bản cho nhiều ứng dụng roku
    -   Tự động mở trường văn bản khi có sẵn tùy chỉnh text
    -   Sao chép, Cắt, Dán từ macOS (bằng bàn phím)
    -   Sao chép, Cắt, Dán + Chỉnh sửa tổng quát trên iOS
-   Báo cáo tốt hơn xoay quanh quyền truy cập và kết nối mạng cục bộ
-   Cải thiện chức năng bàn phím
-   Cải tiến ổn định kết nối

## Sắp ra mắt

-   Thêm tùy chọn nhấn giữ dài cho các phím
    -   Nhấn giữ dài phím mũi tên phải để tua nhanh
    -   Nhấn giữ dài phím mũi tên trái để tua lại
    -   Nhấn giữ dài phím tắt tiếng để tắt tiếng dài
        -   Tùy chỉnh +30 giây tắt tiếng thành tùy chọn 30, 15, 60 giây
        -   Hiển thị biểu ngữ với +30 giây, nhấn x để hủy, chỉ số tiến trình tuyến tính
            -   Hiển thị phía dưới bảng điều khiển chính nên gần với nút tắt tiếng
        -   Hủy khi tắt tiếng lại (và cũng gọi api)
-   Sửa các widgets cho macOS

-   Tương lai: Cung cấp tùy chọn xem đơn giản trên iOS mô phỏng gần gũi với giao diện của siri remote
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Hỗ trợ cả cử chỉ visionos...

## Ý tưởng chung cho tương lai

-   Tạo biểu tượng thanh menu tùy chỉnh

-   Làm thế nào để thực hiện giọng-nói-thành-văn-bản hoặc lệnh giọng nói nói chung?

    -   Cần đảo ngược-engineer giao thức UDP của roku voice remote
    -   Hoặc cần thêm text-to-speech tùy chỉnh với engine nút điều khiển?

-   Tự động Chụp ảnh màn hình

    -   Sử dụng UITests để lấy ảnh chụp thực tế cho tất cả các kích cỡ thiết bị + địa phương
    -   Sử dụng AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w để lấy ảnh chụp trong các khung
    -   Hoặc cách khác
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/


-   Thử nhiều phím hack trên iPad

    -   GCKeyboard cho một
    -   FocusEnvironment cho hai
    -   Đảm bảo rằng bất kỳ giải pháp nào được sử dụng cho iOS không làm hỏng việc nhập văn bản trong tin nhắn/nhập bàn phím

-   UI Tests
    -   Test khi thiết bị được thêm vào, nó được hiển thị trong cửa sổ chọn thiết bị và được Roam lựa chọn
    -   Test giả định người dùng có thể điều hướng đến cài đặt -> thiết bị
    -   Test giả định người dùng có thể điều hướng đến cài đặt -> tin nhắn
    -   Test giả định người dùng có thể điều hướng đến cài đặt -> giới thiệu
    -   Test giả định người dùng có thể chỉnh sửa/xóa thiết bị
    -   Test giả định người dùng có thể nhấn nút khi thiết bị được thêm vào
    -   Test giả định người dùng thấy biểu ngữ cho không có thiết bị khi nó xuất hiện
    -   Test giả định người dùng nhìn thấy liên kết ứng dụng
    -   Tham khảo modelcontainers ở swiftdat testingmodelcontainer
    -   Tham khảo ở đây https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad để cách thiết lập các tests

## Sửa lỗi

-   Tìm ra liệu chuỗi cuộc gọi `nextPacket` có ý nghĩa không.
    -   Thay vì lặp mỗi 10ms và mong đợi thời gian đúng, tôi có nên lặp lại các gói được nhận và cố gắng lên lịch chúng tại thời gian máy chủ `10ms * globalSequenceNumber + startHostTime` và thời gian lấy mẫu `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Sau đó tôi có thể chuyển từ một vòng lặp `for await` trên đồng hồ sang vòng lặp `while !Task.isCancelled` với một `Task.sleep` trong nó.
    -   Okay vậy chúng ta cần lặp mỗi 10 ms và cố gắng lấy gói cuối cùng và sau đó lên lịch nó vào thời điểm đó
    -   Bất cứ khi nào chúng tôi đồng bộ âm thanh
        -   Chúng tôi có thời gian hiển thị cuối cùng + một gói đồng bộ
        -   Ước lượng số gói tiếp theo chúng tôi sẽ gửi + thời gian đồng bộ
            -   Render Time + additional

## Cải thiện thông điệp người dùng xoay quanh quản lý thông tin/trạng thái/khả năng

-   Khi bật thiết bị với WOL và không kết nối sau 5 giây, hoặc khi bật thiết bị và lập tức gặp lỗi, hãy hiển thị thông báo cảnh báo bên dưới thông báo wifi
    -   “Chúng tôi không thể đánh thức Roku của bạn” (Tìm hiểu thêm) (Không hiển thị thông tin này nữa cho thiết bị này), (X)
    -   Tìm hiểu thêm hiển thị một số lý do
        -   Bạn không kết nối cùng một mạng (Hiển thị tên mạng thiết bị cuối cùng. Hỏi người dùng đã kết nối với mạng này)
        -   Thiết bị bạn đang ở chế độ chờ sâu (không được tắt gần đây) và không thể được đánh thức
            -   Thiết bị của bạn không hỗ trợ WWOL và đã kết nối với wifi
            -   Thiết bị của bạn không hỗ trợ WWOL hoặc WOL
        -   Mạng của bạn không được thiết lập để cho phép chúng tôi gửi lệnh đánh thức đến thiết bị
-   Khi nhấp vào nút bị vô hiệu hóa, hiển thị thông báo chỉ ra lý do nó bị vô hiệu hóa
    -   Hiển thị một chỉ số thông tin trên nút để chỉ ra rằng thông tin có thể được nhận khi nó được nhấp?
    -   Chế độ tai nghe vô hiệu -> vì thiết bị không hỗ trợ chế độ tai nghe cho ứng dụng này
    -   Điều khiển âm lượng bị vô hiệu -> vì âm thanh đang được xuất qua HDMI không hỗ trợ điều khiển âm lượng?
-   Khi quét thiết bị và không tìm thấy thiết bị mới nào, hiển thị thông báo cảnh báo bên dưới danh sách thiết bị
    -   “Chúng tôi không thể đánh thức Roku của bạn” (Tìm hiểu lý do), (X)
    -   Tìm hiểu thêm hiển thị một popup với một số lý do có thể xảy ra
        -   Đảm bảo thiết bị của bạn đã bật và kết nối cùng mạng wifi với ứng dụng. Nếu vẫn không hoạt động, hãy thử thêm thiết bị một cách thủ công.
        -   Link https://roam.msd3.io/manually-add-tv.md và https://support.roku.com/article/115001480188 cho thêm khắc phục sự cố hoặc trò chuyện
-   Thêm huy hiệu cho supportsWakeOnWLAN và supportsAudioControls

## Để cập nhật khi ngừng hỗ trợ iOS 17/macOS 14 (Feb 2026)

-   Đi xung quanh và loại bỏ thẻ @available(iOS 18)
-   Sử dụng đặc điểm xem trước (preview traits) để chèn dữ liệu mẫu vào xem trước
-   SwiftData
    -   Sử dụng macro mới #Index cho models
    -   Sử dụng macro mới #Unique cho models
    -   Sử dụng xóa hàng loạt
-   TipKit
    -   Sử dụng CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
