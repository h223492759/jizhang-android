// 登录态事件的追踪钩子（v2.2.25）
//
// 起因：用户反馈「账户会登出」。安卓端全仓只有两处会清登录态（我的页「退出登录」、
// 切换服务器页 selectServer），都带确认或不该被误触 —— 所以必须能拿到**发生时刻的
// 现场证据**，而不是靠猜。
//
// 做法：Storage / SessionNotifier 在读写登录态的关键节点调 AuthTrace.log，由
// AutoRecordService.attachAuthTrace() 把 sink 接到运行日志上（运行日志会同步到服务端，
// 后台不限条数留存）→ 下次再出问题，直接查后台那一行就知道是「启动没读到 token」
// 还是「被谁清了」。
//
// 为什么单独一个文件：state/session.dart 不能反向 import screens/record/auto_record_service.dart
// （后者已经 import 前者，会形成循环依赖），所以中间放一个零依赖的缓冲。

class AuthTrace {
  static void Function(String msg)? sink;

  static final List<String> _pending = [];

  /// 记录一条登录态事件。sink 尚未接上时先缓冲（最多 50 条），接上后补写。
  static void log(String msg) {
    final s = sink;
    if (s != null) {
      s(msg);
      return;
    }
    _pending.add(msg);
    if (_pending.length > 50) _pending.removeAt(0);
  }

  /// 取走缓冲的事件（接上 sink 时调用一次）
  static List<String> drain() {
    final l = List<String>.from(_pending);
    _pending.clear();
    return l;
  }
}
