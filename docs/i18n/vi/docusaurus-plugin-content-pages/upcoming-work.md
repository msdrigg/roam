---
hide_table_of_contents: true
---

# Công việc Roam gần đây nhất

# Cập nhật Roam sắp tới

- Thêm các widget kiểm soát: Phát, Tắt tiếng, Thay đổi âm lượng và Chọn từ Trung tâm kiểm soát!

## Lộ trình

-   Cập nhật xử lý bàn phím để hỗ trợ ecp-textedit trên `KeyboardEntry`
    -   Hiển thị bàn phím khi mở textedit
    -   Ẩn bàn phím khi đóng textedit
    -   Đảm bảo rằng việc dán + chọn/xoá vào trường textedit hoạt động như mong đợi
    -   Sử dụng trường văn bản đã chỉnh sửa hiện tại nếu ecp-textedit không được hỗ trợ, sử dụng trường văn bản chuẩn nếu được hỗ trợ
    -   Trên macOS, hỗ trợ dán bằng cmdP, sao chép/cắt bằng cmdX + cmdC
    -   Nếu ecp-textedit không được hỗ trợ, quay lại hành vi gửi phím hiện tại
    -   Trên macOS, hiển thị một field text dưới cùng khi textedit được kích hoạt 
    -   Trên macOS, cho phép cmd+v và cmd+c và cmd+x để sao chép dán từ/bên ngoài bộ đệm

-   Thêm bộ hẹn giờ tắt tiếng 30 giây kèm theo đếm ngược
    -   Giữ tắt tiếng để tắt tiếng trong vòng +30 giây
    -   Nhấp lại để bỏ tắt tiếng và hủy bỏ nó
    -   Hiển thị một chỉ báo dưới dòng button tắt tiếng 
        -   Than cầu tiến trình có chỉ báo tiến trình tuyến tính
        -   Thanh tiến trình có hai nút: +30 giây, hủy bỏ
        -   Hiển thị bên dưới bảng nút chính vì nó gần với nút tắt tiếng
    -   Đặt +30 có thể cài đặt thành 30, 15, 60 giây tùy chọn tắt tiếng

-   Cung cấp một giao diện Tối giản tùy chọn trên iOS mô phỏng gần như hoàn toàn giao diện điều khiển siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Hỗ trợ cử chỉ visionos cũng như...

## Ý tưởng chung cho tương lai

-   Viết một bài viết blog về bot discord và đưa tới MessageView của tôi
-   Viết một bài viết blog về việc tự dịch và logic xung quanh điều đó

-   Tạo biểu tượng thanh menu tùy chỉnh

-   Làm thế nào để thực hiện chuyển đổi giọng nói thành văn bản hoặc các lệnh giọng nói chung?
    - Cần đảo ngược giao thức udp của remote giọng nói roku
    - Hoặc cần thêm chuyển đổi văn bản thành giọng nói tùy chỉnh với engine button remote?

-   Tự động chụp ảnh màn hình

    -   Sử dụng UITests để nhận ảnh chụp màn hình thực
    -   Sử dụng AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w để màn hình chụp ảnh vào các khung ảnh
    -   Hoặc cái gì đó khác
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Thử nghiệm thêm bàn phím
    -   GCKeyboard cho một
    -   FocusEnvironment cho 2
    -   Đảm bảo rằng bất kể phương pháp nào được sử dụng cho iOS không làm hỏng khả năng nhập văn bản trong tin nhắn/nhập bàn phím

-   Thêm tracking sự kiện thông qua hành vi người dùng thực sự đang làm trên thiết bị của họ (kết nối với phân tích firebase có lẽ?)
    -   Theo dõi ai đang sử dụng giao diện tối giản, họ đang thực hiện những hành động gì, v.v...

## Sửa lỗi

-   Xác định xem vòng lặp các cuộc gọi đến `nextPacket` có cần thiết không.
    -   Thay vì lặp sau mỗi 10ms và hy vọng thời gian là chính xác, tôi có nên lặp qua các gói tin nhận được và cố gắng lên lịch chúng vào thời điểm máy chủ `10ms * globalSequenceNumber + startHostTime` và sampleTime đến `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Sau đó, tôi có thể chuyển từ một vòng lặp `for await` là dòng h trên bộ đếm giờ đến một vòng lặp `while !Task.isCancelled` với một `Task.sleep` trong đó.
    -   Okay vậy cần phải lặp sau mỗi 10 ms và cố gắng kéo gói cuối cùng và lên lịch nó tại thời điểm đó
    -   Bất cứ khi nào ta làm một audio sync
        -   Chúng ta có lastRenderTime + một gói sync
        -   Ước lượng số gói mà chúng ta nên gửi ra lúc + thời gian đồng bộ
            -   Thời gian Render + bổ sung

## Cải thiện việc kiểm tra

-   UI Tests
    -   Kiểm tra khi thiết bị được thêm nó xuất hiện trong chọn thiết bị và được chọn bởi roam
    -   Kiểm tra người dùng có thể điều hướng tới cài đặt -> thiết bị
    -   Kiểm tra người dùng có thể điều hướng tới cài đặt -> tin nhắn
    -   Kiểm tra người dùng có thể điều hướng tới cài đặt -> về
    -   Kiểm tra người dùng có thể chỉnh sửa/xóa thiết bị
    -   Kiểm tra người dùng có thể nhấn nút sau khi thiết bị được thêm
    -   Kiểm tra người dùng nhìn thấy banner cho không có thiết bị khi nó xuất hiện
    -   Kiểm tra người dùng nhìn thấy applinks
    -   Xem swiftdat testingmodelcontainer cho modelcontainers
    -   Xem tại đây https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad để cách thiết lập các bài kiểm tra

## App Clip

-   AppClip
    -   Thêm nút "getAShareableLinkToThisDevice" trên cài đặt -> thiết bị
        -   Tạo sẵn tất cả 1.1M mã AppClip và mã hóa vị trí nhẫn (0.5GB)
        -   Làm một nút "Lấy link chia sẻ cho thiết bị này!" với một xem trước ảnh để mã AppClip (màu Roam)
        -   Tải mã + liên kết và chuyển đổi thành PNG trên thiết bị khi vị trí thiết bị thay đổi
        -   Giữ chuẩn mã mở thiết bị như một link chia sẻ hình ảnh (với mã xem trước!)
    -   Cũng làm cho liên kết thiết bị thực sự có thể chia sẻ

## Cải thiện thông điệp người dùng xung quanh quản lý thông tin/trạng thái

-   Cập nhật Quản lý thông tin/trạng thái để xử lý tốt hơn trạng thái không ổn định
    -   Khi ngắt kết nối, chọn, nhấp nút, chuyển sang chế độ foreground, mở ứng dụng -> Khởi động lại vòng lặp kết nối lại nếu bị ngắt kết nối
    -   Vòng lặp kết nối lại là để quay lại cố gắng kết nối thất bại (0.5s, double, 10s hiệp định)
    -   Khi kết nối với thiết bị, luôn vô hiệu hóa các cảnh báo mạng
    -   Khi cố gắng kết nối với thiết bị, hoặc cố gắng bật thiết bị, hiển thị biểu tượng thông tin đang xoay thay vì dấu chấm màu xám
    -   Khi bật thiết bị và thành công, hiển thị một hoạt ảnh khi chuyển đổi từ màu xám -> xoay -> màu xanh
    -   Khi bật thiết bị với WOL và không kết nối sau 5 giây, hoặc khi bật thiết bị và ngay lập tức thất bại, hiển thị một thông điệp cảnh báo dưới cầu thông tin wifi
        -   “Chúng tôi không thể đánh thức Roku” (Tìm hiểu thêm) (Không hiển thị lại với thiết bị này), (X)
        -   Tìm hiểu thêm hiển thị một số lý do tại sao
            -   Bạn không được kết nối với cùng một mạng (Hiển thị tên mạng thiết bị cuối cùng. Hỏi xem người dùng đã kết nối với mạng này chưa)
            -   Thiết bị của bạn đang trong giấc ngủ sâu (không được tắt gần đây) và không thể được đánh thức
                -   Thiết bị của bạn không hỗ trợ WWOL và được kết nối với wifi
                -   Thiết bị của bạn không hỗ trợ WWOL hoặc WOL
            -   Mạng của bạn không được thiết lập theo cách cho phép chúng tôi gửi lệnh đánh thức tới thiết bị
    -   Vòng lặp kết nối lại = Thử lại Exponentially cố gắng kết nối lại ECP
        -   Kết nối lại ECP đầu tiên
        -   Nghe notify thứ hai
            -   Xử lý +power-mode-changed,+textedit-opened,+textedit-changed,+textedit-closed,+device-name-changed
            -   Đảm bảo chúng ta có thể xử lý từng yêu cầu này và định dạng của chúng…
        -   Làm mới trạng thái thiết bị thứ ba
        -   Làm mới query-textedit-state thứ tư
            -   Cập nhật trạng thái textedit
        -   Làm mới biểu tượng thiết bị thứ năm
    -   Trên tất cả thay đổi sau khi kết nối lại (thông qua notify hoặc bất cứ gì)
        -   Cập nhật Thiết bị (được lưu trữ) và DeviceState (voilatile)
    -   Sau khi kết nối lại/ngắt kết nối, cập nhật trạng thái trực tuyến trong giao diện remote

## Cải thiện thông điệp người dùng xung quanh khả năng của thiết bị

-   Cập nhật thông điệp người dùng khi có thể xảy ra lỗi
    -   Khi nhấp vào một nút bị vô hiệu hóa, mở popover để hiển thị tại sao nó bị vô hiệu hóa
        -   Hiển thị một chỉ báo thông tin trên nút để chỉ ra rằng thông tin có thể nhận được khi nó được nhấp?
        -   Chế độ tai nghe bị vô hiệu hóa -> vì thiết bị không hỗ trợ chế độ tai nghe để ứng dụng này
        -   Kiểm soát âm lượng bị vô hiệu hóa -> vì âm thanh được xuất ra qua HDMI, không hỗ trợ kiểm soát âm lượng?
    -   Khi đang quét thiết bị một cách chủ động và không tìm thấy thiết bị mới nào, hiển thị một thông điệp cảnh báo phía dưới danh sách thiết bị
        -   “Chúng tôi không thể đánh thức Roku” (Tìm hiểu vì sao), (X)
        -   Tìm hiểu thêm hiển thị một hộp thoại với một số lý do tại sao điều này có thể xảy ra
            -   Đảm bảo thiết bị của bạn được kích hoạt và kết nối với cùng một mạng wifi với ứng dụng của bạn. Nếu vẫn không hoạt động, hãy thử thêm thiết bị bằng tay.
            -   Liên kết https://roam.msd3.io/manually-add-tv.md và https://support.roku.com/article/115001480188 cho thêm bước khắc phục sự cố hoặc trò chuyện
-   Thêm huy hiệu cho supportsWakeOnWLAN và supportsMute

## Ghi chú textedit ECP

Keyboard ECP Session Commands (notes)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## Cập nhật khi ngừng hỗ trợ cho iOS 17/macOS 14 (Feb 2026)

-   Đi xung quanh và loại bỏ các thẻ @available(iOS 18)
-   Sử dụng tính chất xem trước để chèn dữ liệu mẫu vào xem trước
    -   Làm thế nào để làm điều này với iOS 17 vẫn là yếu tố?
    -   Làm thế nào để sử dụng @Previewable trong xem trước với iOS 17 vẫn là yếu tố??
-   SwiftData
    -   Sử dụng #Index macro mới cho models
    -   Sử dụng #Unique macro mới cho models
    -   Sử dụng xoá hàng loạt
-   TipKit
    -   Sử dụng CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
