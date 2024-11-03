---
hide_table_of_contents: true
---

# Công việc gần đây nhất trên Roam

# Những cập nhật sắp tới của Roam

## Cải tiến chung

-   Cập nhật các bản dịch để đảm bảo tất cả đều đạt 100%
-   Tài liệu bot hỗ trợ discord và có thể nhân bản nó thành một thư viện
-   Tạo biểu tượng thanh menu bạn tùy chỉnh 

-   Làm thế nào để sử dụng giọng nói để nhập văn bản hoặc lệnh giọng nói 
    - Cần đảo ngược kỹ thuật protocol udp từ remote giọng nói roku
    - Hoặc cần thêm văn bản tùy chỉnh để tổ chức với engine nút remote?

-   Thêm hẹn giờ tắt tiếng +30 giây với đếm ngược
    -   Giữ nút tắt tiếng để tắt tiếng trong +30 giây
    -   Nhấp lại để hủy tắt tiếng
    -   Hiện thông báo trên thanh trên cùng
        -   Thanh tiến trình có chỉ thị tiến trình tuyến tính
        -   Thanh tiến trình có hai nút: +30 giây và hủy
        -   Hiển thị dưới bảng nút chính, gần với nút tắt tiếng
    -   Đặt số +30 có thể cấu hình thành các tùy chọn tắt tiếng 30, 15 hoặc 60 giây

-   Tự động chụp ảnh màn hình
    -   Sử dụng UITests để có được ảnh chụp thực sự 
    -   Sử dụng AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w để có các ảnh chụp trong các khung
    -   Hoặc một số thứ khác
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Thử nghiệm nhiều hack bàn phím
    -   GCKeyboard để mở đầu
    -   Môi trường tập trung cho số 2
    -   Đảm bảo rằng giải pháp nào được sử dụng cho iOS không làm hỏng việc nhập văn bản trong các tin nhắn /việc nhập từ bàn phím
    
-   Thực hiện AppIntents trên iOS 18
    -   Thêm các app intents vào trung tâm điều khiển
        -   Sử dụng toggle cho mute/unmute và power on/off
        -   Sử dụng các nút cho tất cả mọi thứ khác
        -   Sử dụng màu tím chính xác
        -   Đặt cấu hình giống như các widget
        -   Làm việc với gợi ý hành động
    -   Cho phép siri / spotlight xem tốt hơn các thứ trong ứng dụng của tôi?
        -   Thêm liên kết phổ quát cho các thiết bị để siri có thể liên kết đến chúng?
        -   Đảm bảo rằng tìm kiếm ngữ nghĩa hoạt động
        -   Thực hiện chuyển tiếp qua chuỗi / mã có thể mã hoá cho các thực thể của ứng dụng của tôi
            -   Đại diện Proxy
            -   Đại diện có thể mã hóa
-   Cung cấp một tùy chọn xem tối giản tyêu chọn trên iOS mô phỏng gần như tương đối với giao diện siri remote
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Hỗ trợ cả cử chỉ của visionos nữa...
    -   Cần xây dựng api textedit trước
-   Thêm một số theo dõi sự kiện về những hành động mà người dùng thực sự đang thực hiện trên các thiết bị của họ (kết nối với google analytics có thể?)
    -   Theo dõi ai đang sử dụng chế độ xem tối giản, những hành động mà họ đang thực hiện, v.v…

## Sửa lỗi

-   Tìm ra liệu chuỗi lệnh tới `nextPacket` có hợp lý không.
    -   Thay vì lặp đi lặp lại mỗi 10ms và hy vọng thời gian là chính xác, có lẽ tôi nên lặp lại qua các gói đã nhận và cố gắng lên lịch chúng tại `10ms * globalSequenceNumber + startHostTime` và thời gian mẫu tới `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Sau đó, tôi có thể chuyển từ vòng lặp `for await` qua đồng hồ sang vòng lặp `while !Task.isCancelled` với `Task.sleep` ở trong.
    -   Vậy nên chúng tôi cần lặp lại mỗi 10 ms và cố gắng lấy gói cuối cùng ra và sau đó lên lịch nó vào thời gian đó
    -   Bất kỳ khi nào chúng ta làm đồng bộ âm thanh
        -   Chúng ta có thời gian render cuối cùng + gói đồng bộ
        -  Ước lượng số gói mà chúng ta nên gửi ra và + thời gian đồng bộ
            -   Thời gian render + thêm

## Cải thiện việc kiểm tra

-   Kiểm tra giao diện người dùng
    -   Kiểm tra khi thiết bị được thêm là nó hiển thị trong bộ chọn thiết bị và được chọn bởi Roam
    -   Kiểm tra người dùng có thể điều hướng đến cài đặt -> thiết bị không
    -   Kiểm tra người dùng có thể điều hướng đến cài đặt -> tin nhắn không
    -   Kiểm tra người dùng có thể điều hướng đến cài đặt -> giới thiệu không 
    -   Kiểm tra người dùng có thể chỉnh sửa / xóa các thiết bị không
    -   Kiểm tra người dùng có thể nhấp vào các nút một khi các thiết bị đã được thêm không 
    -   Kiểm tra người dùng thấy banner hiển thị cho không có thiết bị khi nó hiển thị
    -   Kiểm tra người dùng có thấy applinks không 
    -   Tham khảo swiftdat testingmodelcontainer cho modelcontainers
    -   Tham khảo tại đây https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad để cách thiết lập kiểm tra

## App Clip

-   AppClip
    -   Thêm nút "getAShareableLinkToThisDevice" trên cài đặt -> thiết bị
        -   Tiền tạo tất cả 1,1M mã app clip và mã hoá vị trí vòng (0,5GB)
        -   Tạo một nút để "Lấy một liên kết có thể chia sẻ đến thiết bị!" với xem trước hình ảnh đến mã app clip (màu Roam)
        -   Tải xuống mã+liên kết và chuyển đổi thành PNG trên thiết bị khi một vị trí thiết bị thay đổi   
        -   Làm cho mã mở thiết bị như một liên kết chia sẻ đến hình ảnh  (với xem trước!)
    -   Cũng làm cho liên kết thiết bị thực sự có thể chia sẻ

## Cải thiện tin nhắn người dùng xung quanh việc quản lý thông tin / trạng thái

-   Cập nhật quản lý thông tin / trạng thái để xử lý tốt hơn trạng thái không ổn định
    -   Khi ngắt kết nối, chọn, bấm nút, di chuyển vào cửa hàng, mở ứng dụng -> Khởi động lại vòng lặp kết nối lại nếu ngắt kết nối
    -   Vòng lặp kết nối lại là để làm việc bù trừ lớp hóa để thử lại các kết nối bị hỏng (0,5s, gấp đôi, 10s bù trừ)
    -   Khi đã kết nối tới thiết bị, luôn tắt cảnh báo mạng
    -   Khi cố kết nối tới thiết bị, hoặc cố bật thiết bị, hiện biểu tượng thông tin đang quay thay vì chấm màu xám
    -   Khi bật thiết bị và thành công, hiển thị một hoạt ảnh trên sự chuyển đổi từ xám -> quay -> xanh
    -   Khi bật thiết bị với WOL và không kết nối sau 5 giây, hoặc khi bật thiết bị và tức thì thất bại, hiển thị một thông điệp cảnh báo nằm dưới thông điệp cảnh báo wifi
        -   “Chúng tôi không thể đánh thức Roku của bạn” (Tìm hiểu thêm) (Đừng hiển thị lại cho thiết bị này), (X)
        -   Tìm hiểu thêm hiển thị một số lý do tại sao
            -   Bạn không kết nối với mạng hiện tại (hiển thị tên mạng thiết bị cuối cùng. Hỏi người dùng có kết nối với mạng này không)
            -   Thiết bị của bạn đang trong giấc ngủ sâu (không được tắt gần đây) và không thể được đánh thức
                -   Thiết bị của bạn không hỗ trợ WWOL và được kết nối với wifi
                -   Thiết bị của bạn không hỗ trợ WWOL hoặc WOL
            -   Mạng của bạn không được thiết lập theo cách cho phép chúng tôi gửi lệnh đánh thức tới thiết bị
    -   Vòng lặp kết nối lại = Backing off Exponentially attempt to reconnect to reconnect ECP
        -   Kết nối ECP đầu tiên
        -   Lắng nghe thông báo thứ hai
            -   Xử lý +power-mode-changed,+textedit-opened,+textedit-changed,+textedit-closed,+device-name-changed
            -   Đảm bảo rằng chúng tôi có thể xử lý mỗi yêu cầu này và định dạng của chúng…
        -   Làm mới trạng thái thiết bị thứ ba
        -   Làm mới query-textedit-state thứ tư
            -   Cập nhật trạng thái textedit
        -   Làm mới biểu tượng thiết bị thứ năm
    -   Trên tất cả những thay đổi sau khi kết nối lại (thông qua thông báo hoặc bất cứ điều gì)
        -   Cập nhật thiết bị (đã lưu) và trạng thái thiết bị (volatile)
    -   Sau khi kết nối / ngắt kết nối, cập nhật trạng thái trực tuyến trong chế độ xem từ xa

## Cải thiện thông điệp người dùng xung quanh khả năng của thiết bị

-   Cập nhật tin nhắn người dùng khi có thể xảy ra lỗi
    -   Khi nhấp vào một nút không hoạt động, mở yêu cầu để hiển thị lý do tại sao nó bị vô hiệu hóa
        -   Hiển thị chỉ số thông tin trên nút để chỉ ra rằng thông tin có thể được nhận khi nó được nhấp vào?
        -   Chế độ tai nghe bị vô hiệu hóa -> vì thiết bị không hỗ trợ chế độ tai nghe đến ứng dụng này
        -   Kiểm soát âm lượng bị vô hiệu hóa -> vì âm thanh đang được xuất ra qua HDMI không hỗ trợ kiểm soát âm lượng.
    -   Khi đang quét activly cho các thiết bị và không tìm thấy thiết bị mới nào, hiển thị một thông điệp cảnh báo bên dưới danh sách thiết bị
        -   "Chúng tôi không thể đánh thức Roku của bạn" (Tìm hiểu lý do), (X)
        -   Tìm hiểu thêm hiển thị một cửa sổ bật lên với một số lý do tại sao điều này có thể đang xảy ra
            -   Đảm bảo rằng thiết bị của bạn đang được bật và kết nối với cùng một mạng wifi với ứng dụng của bạn. Nếu vấn đề này vẫn không được giải quyết, hãy thử thêm thiết bị một cách thủ công.
            -   Liên kết https://roam.msd3.io/manually-add-tv.md và https://support.roku.com/article/115001480188 để giải quyết sự cố hoặc trò chuyện thêm
-   Thêm huy hiệu cho supportsWakeOnWLAN và supportsMute

## Hỗ trợ textedit ecp

-   Cập nhật việc xử lý bàn phím để hỗ trợ ecp-textedit trên `KeyboardEntry`
    -   Hiển thị bàn phím khi textedit được mở
    -   Ẩn bàn phím khi textedit đóng
    -   Kiểm tra việc dán+chọn/xóa vào trường textedit hoạt động như mong đợi 
    -   Nếu hỗ trợ ecp-textedit, cho phép chọn, xóa văn bản và di chuyển con trỏ. Chỉ gửi lại văn bản mỗi khi nó thay đổi nếu điều này được hỗ trợ.
    -   Nếu ecp-textedit không được hỗ trợ, quay lại hành vi hiện tại của việc gửi các phím
    -   Trên macOS ,hiển thị một chỉ số khi textedit được kích hoạt
    -   Trên macOS, cho phép cmd + v và cmd + c và cmd + x để sao chép dán từ / vào bộ đệm

Lệnh phiên ecp bàn phím (ghi chú)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## Để cập nhật khi ngừng hỗ trợ cho iOS 17/macOS 15 (2025)

-   Sử dụng thuộc tính xem trước để chèn dữ liệu mẫu vào các xem trước
    -   Làm thế nào để thực hiện điều này với iOS 17 vẫn còn là yếu tố?
    -   Làm thế nào để sử dụng @Previewable trong các xem trước với iOS 17 vẫn còn là yếu tố??
-   SwiftData
    -   Sử dụng chế độ #Index mới cho các mô hình
    -   Sử dụng chế độ #Unique mới cho các mô hình
    -   Sử dụng xóa hàng loạt
-   TipKit
    -   Sử dụng CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
