import UIKit
import Flutter
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
    var splashWindow: UIWindow?
    var privacyWindow: UIWindow?
    private let fileShareChannel = "player/file_share"
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 注册 Flutter 插件
        GeneratedPluginRegistrant.register(with: self)
        
        // 调用父类方法，完成 Flutter 和 iOS 启动流程
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
        configureBackgroundPlaybackAudioSession()
        registerFileShareChannel()
        
        // 创建覆盖启动图的浮层窗口
        splashWindow = UIWindow(frame: UIScreen.main.bounds)
        splashWindow?.rootViewController = UIViewController()
        splashWindow?.windowLevel = UIWindow.Level.statusBar + 1
        splashWindow?.backgroundColor = UIColor.white
        splashWindow?.isHidden = false

        let launchImageView = UIImageView()
        launchImageView.image = UIImage(named: "launchBg") // 启动图
        launchImageView.contentMode = .scaleAspectFit
        launchImageView.translatesAutoresizingMaskIntoConstraints = false // 开启 Auto Layout
        splashWindow?.addSubview(launchImageView)

        // 添加自动布局约束：居中，宽高不超过屏幕尺寸
        if let splashWindow = splashWindow {
            NSLayoutConstraint.activate([
                launchImageView.centerXAnchor.constraint(equalTo: splashWindow.centerXAnchor),
                launchImageView.centerYAnchor.constraint(equalTo: splashWindow.centerYAnchor),
                launchImageView.widthAnchor.constraint(equalToConstant: 120),
                launchImageView.heightAnchor.constraint(equalToConstant: 120)
            ])
        }
        
        // 延迟淡出启动图
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            UIView.animate(withDuration: 0.35, animations: {
                self.splashWindow?.alpha = 0
            }, completion: { _ in
                self.splashWindow?.isHidden = true
                self.splashWindow = nil
            })
        }
        
        return result
    }

    private func configureBackgroundPlaybackAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback)
            try audioSession.setActive(true)
        } catch {
            NSLog("Failed to configure background playback audio session: \(error.localizedDescription)")
        }
    }

    private func registerFileShareChannel() {
        guard let controller = window?.rootViewController as? FlutterViewController else {
            return
        }

        let channel = FlutterMethodChannel(
            name: fileShareChannel,
            binaryMessenger: controller.binaryMessenger
        )
        channel.setMethodCallHandler { [weak self, weak controller] call, result in
            guard call.method == "shareFile" else {
                result(FlutterMethodNotImplemented)
                return
            }

            guard
                let args = call.arguments as? [String: Any],
                let path = args["path"] as? String,
                !path.isEmpty
            else {
                result(FlutterError(
                    code: "invalid_path",
                    message: "File path is empty",
                    details: nil
                ))
                return
            }

            guard FileManager.default.fileExists(atPath: path) else {
                result(FlutterError(
                    code: "missing_file",
                    message: "File does not exist",
                    details: path
                ))
                return
            }

            guard let controller else {
                result(FlutterError(
                    code: "missing_controller",
                    message: "Root controller is not available",
                    details: nil
                ))
                return
            }

            self?.shareFile(
                at: URL(fileURLWithPath: path),
                title: args["title"] as? String,
                from: controller,
                result: result
            )
        }
    }

    private func shareFile(
        at url: URL,
        title: String?,
        from controller: UIViewController,
        result: @escaping FlutterResult
    ) {
        let activityController = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        activityController.title = title

        if let popover = activityController.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(
                x: controller.view.bounds.midX,
                y: controller.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }

        controller.present(activityController, animated: true) {
            result(nil)
        }
    }

    override func applicationWillResignActive(_ application: UIApplication) {
        showPrivacyWindow()
        super.applicationWillResignActive(application)
    }

    override func applicationDidEnterBackground(_ application: UIApplication) {
        showPrivacyWindow()
        super.applicationDidEnterBackground(application)
    }

    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.hidePrivacyWindow()
        }
    }

    private func showPrivacyWindow() {
        if privacyWindow != nil {
            return
        }

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.windowLevel = UIWindow.Level.alert + 1
        window.backgroundColor = UIColor.white
        window.isHidden = false

        let label = UILabel()
        label.text = "helloworld"
        label.textColor = UIColor.black
        label.font = UIFont.systemFont(ofSize: 18, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: window.centerYAnchor)
        ])

        privacyWindow = window
    }

    private func hidePrivacyWindow() {
        privacyWindow?.isHidden = true
        privacyWindow = nil
    }
}
