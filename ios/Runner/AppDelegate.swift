import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
    var splashWindow: UIWindow?
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 注册 Flutter 插件
        GeneratedPluginRegistrant.register(with: self)
        
        // 调用父类方法，完成 Flutter 和 iOS 启动流程
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
        
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
                launchImageView.widthAnchor.constraint(lessThanOrEqualTo: splashWindow.widthAnchor),
                launchImageView.heightAnchor.constraint(lessThanOrEqualTo: splashWindow.heightAnchor)
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
}
