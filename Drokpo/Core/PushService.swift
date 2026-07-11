import FirebaseAuth
import FirebaseMessaging
import UIKit
import UserNotifications

/// Keeps this device's FCM token registered with the backend
/// (POST/DELETE /api/profile/me/fcm-tokens) so the Cloud Functions can push
/// "new match" and "new message" notifications.
final class PushService: NSObject {
    static let shared = PushService()

    /// Latest token minted by FCM; may rotate at any time.
    private var currentToken: String?
    /// Token the backend currently has for this device.
    private var uploadedToken: String?

    /// Hook up delegates; call once at launch, after FirebaseApp.configure().
    func configure() {
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
    }

    /// Ask for notification permission and sync the token. Called every time
    /// the session becomes active; the system prompt only shows once.
    func enable() {
        Task { @MainActor in
            let options: UNAuthorizationOptions = [.alert, .badge, .sound]
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: options)) ?? false
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
            self.uploadTokenIfNeeded()
        }
    }

    /// Detach this device from the profile; call before signing out, while the
    /// auth session is still valid.
    func unregister() async {
        guard let token = uploadedToken ?? currentToken else { return }
        let _: EmptyResponse? = try? await APIClient.shared.delete(
            "/api/profile/me/fcm-tokens",
            query: [URLQueryItem(name: "token", value: token)]
        )
        uploadedToken = nil
    }

    private func uploadTokenIfNeeded() {
        guard let token = currentToken, token != uploadedToken,
              Auth.auth().currentUser != nil else { return }
        Task {
            do {
                let _: EmptyResponse = try await APIClient.shared.post(
                    "/api/profile/me/fcm-tokens",
                    body: FcmTokenIn(token: token)
                )
                self.uploadedToken = token
            } catch {
                // Retried on the next enable() or token rotation.
            }
        }
    }
}

extension PushService: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        currentToken = fcmToken
        uploadTokenIfNeeded()
    }
}

extension PushService: UNUserNotificationCenterDelegate {
    // Show notifications as banners even while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    // Notification tap (including cold-start — the delegate is set at launch).
    // FCM data payloads arrive as top-level keys in userInfo.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let type = userInfo["type"] as? String
        let matchId = userInfo["matchId"] as? String
        guard type != nil || matchId != nil else { return }
        await MainActor.run {
            DeepLinkRouter.shared.handle(type: type, matchId: matchId)
        }
    }
}
