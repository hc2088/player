import 'dart:async';
import 'package:event_bus/event_bus.dart';

/// 全局 EventBus 实例
final EventBus eventBus = EventBus();

/// 抽象事件基类，包含事件名字段
abstract class NamedEvent {
  final String name;

  NamedEvent(this.name);
}

/// 收藏状态变更事件（示例）
class FavoriteChangedEvent extends NamedEvent {
  final String url;
  final bool isFavorite;

  FavoriteChangedEvent({
    required String name,
    required this.url,
    required this.isFavorite,
  }) : super(name);
}

/// 事件订阅帮助函数，只监听指定名称的事件
StreamSubscription<T> listenNamedEvent<T extends NamedEvent>({
  required String name,
  required void Function(T event) onData,
}) {
  return eventBus.on<T>().listen((event) {
    if (event.name == name) {
      onData(event);
    }
  });
}

/// 发送事件
void emitEvent(NamedEvent event) {
  eventBus.fire(event);
}
