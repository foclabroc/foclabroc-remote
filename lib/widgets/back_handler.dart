// Gestionnaire global de bouton retour par onglet
class TabBackHandler {
  static final Map<int, bool Function()> _handlers = {};

  static void register(int tabIndex, bool Function() handler) {
    _handlers[tabIndex] = handler;
  }

  static void unregister(int tabIndex) {
    _handlers.remove(tabIndex);
  }

  static bool hasHandler(int tabIndex) => _handlers.containsKey(tabIndex);

  static bool handle(int tabIndex) {
    final handler = _handlers[tabIndex];
    if (handler != null) return handler();
    return false;
  }
}
