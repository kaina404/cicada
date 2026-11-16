> Mac 配对二维码已改为打开免安装的[局域网控制页](../docs/remote-web.md)。原生 iPhone App 也可扫描或粘贴同一个配对链接。

# Cicada Remote for iPhone

1. Open [AssistantSentenceControl.xcodeproj](AssistantSentenceControl.xcodeproj) in Xcode. Select your iPhone and run the **AssistantSentenceControl** scheme using your development signing team. The app requires iOS 18 or later.
2. Open **Floating Answer** on the updated Mac app and enable **Read along**. Connect your headphones to the Mac.
3. Put the iPhone and Mac on the same trusted Wi-Fi. In the Mac floating window, click the phone icon and generate a pairing code. In **Cicada Remote**, scan the code and allow local network access. You can also paste the pairing link.
4. The iPhone highlights and scrolls to the word currently playing on the Mac. The three equal-height buttons on the right are **Previous sentence**, **Hold to play**, and **Next sentence**, from top to bottom. Switching sentences is silent. Hold to listen through the Mac headphones and release to pause. Swipe on the answer to move the Mac window.
5. If automatic answering stalls, tap **重新生成** (Regenerate). Mac cancels the old request and generates a fresh answer from the latest question, including partial recognition. Read along is not required; you can request again while generation is running. The button is unavailable until Mac has question or screen context.
6. To view the desktop, select **Share the Mac main display with iPhone** in the Mac floating window’s phone menu, then tap **Mac 屏幕** on iPhone. Allow Screen Recording for Cicada in macOS System Settings if prompted. The phone shows live JPEG images of the main display. Use the same Mac menu to stop sharing.

Closing or hiding Floating Answer clears the answer on the phone and stops remote playback. Reopen it to resume with a fresh gesture. A lost connection or backgrounded phone also stops remote playback. The Mac's **Disconnect iPhone** button revokes the current code. Generating a new code revokes the old one. After pairing once, reopen either app to reconnect automatically on the same Wi-Fi. If the Mac is offline, the iPhone retries while open. To forget the pairing on iPhone, tap **断开**. Start screen sharing from the Mac menu each time you need it after a Mac restart.

The phone uses the existing LAN receiver and the same control packets as the Apple Watch. The Mac streams no audio to the phone. The pairing link grants access to the visible answer, controls, and explicitly enabled desktop preview over local HTTP, so keep the link private and use a trusted network. Screen sharing ends when the Mac float is hidden, the Mac locks or sleeps, or the pairing is revoked. Cicada windows marked private are excluded.
