#pragma once

#include <QEvent>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QObject>
#include <QQuickItem>
#include <QQuickWindow>
#include <QVariant>
#include <QDebug>
#include <chrono>

namespace lunchpail {

// The SC2 can expose a keyboard alongside its native gamepad interface. Qt
// receives the keyboard key through the normal window path, while SDL3 emits
// the same navigation action independently. Observe, but never consume, keys
// so the gamepad router can coalesce matching actions from those two paths.
inline int navigationActionForKey(int key) {
    switch (key) {
    case Qt::Key_Up: return 1;
    case Qt::Key_Down: return 2;
    case Qt::Key_Left: return 3;
    case Qt::Key_Right: return 4;
    case Qt::Key_Return:
    case Qt::Key_Enter:
    case Qt::Key_Space: return 5;
    case Qt::Key_Escape:
    case Qt::Key_Backspace: return 6;
    default: return 0;
    }
}

struct KeyboardNavigationObservation {
    int action = 0;
    std::chrono::steady_clock::time_point when;
};

inline KeyboardNavigationObservation& lastKeyboardNavigation() {
    static KeyboardNavigationObservation observation;
    return observation;
}

inline const char* directionForKey(int key) {
    switch (key) {
    case Qt::Key_Up: return "up";
    case Qt::Key_Down: return "down";
    case Qt::Key_Left: return "left";
    case Qt::Key_Right: return "right";
    default: return nullptr;
    }
}

class GamepadKeyboardObserver final : public QObject {
public:
    explicit GamepadKeyboardObserver(QObject* parent) : QObject(parent) {}
    bool eventFilter(QObject* watched, QEvent* event) override {
        if (event->type() != QEvent::KeyPress) return false;
        auto* key = static_cast<QKeyEvent*>(event);
        const auto action = navigationActionForKey(key->key());
        if (action != 0) lastKeyboardNavigation() = {action, std::chrono::steady_clock::now()};
        // Arrow keys move like the gamepad d-pad/stick. Let the focused item
        // use them first (grids, lists, text fields, sliders); when nothing
        // accepts the key, hand it to the window's gamepad router instead.
        const char* direction = directionForKey(key->key());
        auto* window = qobject_cast<QQuickWindow*>(watched);
        const auto modifiers = key->modifiers() & ~Qt::KeypadModifier;
        if (!direction || !window || modifiers != Qt::NoModifier || delivering) return false;
        delivering = true;
        key->setAccepted(false);
        static_cast<QObject*>(window)->event(key);
        delivering = false;
        // One line per arrow press: which item had focus and whether it used
        // the key. Lets a "keys do nothing" report be diagnosed from the log.
        {
            QObject* focus = window->activeFocusItem();
            qInfo("LUNCHPAIL_ARROW_KEY key=%s focus=%s name=%s accepted=%d", direction,
                  focus ? focus->metaObject()->className() : "none",
                  focus ? qPrintable(focus->objectName()) : "",
                  key->isAccepted() ? 1 : 0);
        }
        if (!key->isAccepted()) {
            QMetaObject::invokeMethod(window, "unhandledNavigationKey",
                                      Q_ARG(QVariant, QVariant(QString::fromLatin1(direction))));
            key->accept();
        }
        return true;
    }

private:
    bool delivering = false;
};

inline void installGamepadKeyboardObserver() {
    auto* application = QGuiApplication::instance();
    if (!application || application->property("_lunchpailGamepadKeyboardObserver").toBool()) return;
    application->setProperty("_lunchpailGamepadKeyboardObserver", true);
    application->installEventFilter(new GamepadKeyboardObserver(application));
}

inline bool keyboardNavigationSeenRecently(int action, int maxAgeMs) {
    const auto& observation = lastKeyboardNavigation();
    return action != 0 && observation.action == action && maxAgeMs > 0
        && std::chrono::steady_clock::now() - observation.when
               <= std::chrono::milliseconds(maxAgeMs);
}

} // namespace lunchpail
