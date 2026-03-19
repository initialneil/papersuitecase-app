import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/paper.dart';
import '../models/chat_message.dart';
import '../providers/app_state.dart';

class PaperChatPanel extends StatefulWidget {
  final Paper paper;

  const PaperChatPanel({super.key, required this.paper});

  @override
  State<PaperChatPanel> createState() => _PaperChatPanelState();
}

class _PaperChatPanelState extends State<PaperChatPanel> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendMessage(AppState appState) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    appState.sendChatMessage(widget.paper, text);
    _focusNode.requestFocus();
    // Auto-scroll after a short delay to allow the list to rebuild
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final messages = appState.getChatHistory(widget.paper.id ?? 0);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Auto-scroll when messages change
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Container(
      width: 350,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: colorScheme.outlineVariant),
        ),
        color: colorScheme.surface,
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(appState, colorScheme, theme),
          // Usage indicator
          _buildUsageIndicator(appState, colorScheme, theme),
          const Divider(height: 1),
          // Messages
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState(theme, colorScheme)
                : _buildMessageList(messages, theme, colorScheme),
          ),
          // Loading indicator
          if (appState.isChatLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Thinking...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          // Input
          _buildInputArea(appState, colorScheme, theme),
        ],
      ),
    );
  }

  Widget _buildHeader(
      AppState appState, ColorScheme colorScheme, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.chat, size: 20, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Chat about this paper',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.paper.id != null)
            IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 18, color: colorScheme.onSurfaceVariant),
              onPressed: () => appState.clearChatHistory(widget.paper.id!),
              tooltip: 'Clear chat',
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            icon: Icon(Icons.close,
                size: 18, color: colorScheme.onSurfaceVariant),
            onPressed: () => appState.toggleChatPanel(),
            tooltip: 'Close chat',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildUsageIndicator(
      AppState appState, ColorScheme colorScheme, ThemeData theme) {
    final used = appState.llmCallsThisMonth;
    final limit = appState.llmCallsLimit;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Text(
            '$used/$limit calls this month',
            style: theme.textTheme.bodySmall?.copyWith(
              color: used >= limit
                  ? colorScheme.error
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          if (appState.userTier == 'free') ...[
            const Spacer(),
            Text(
              'Free tier',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.question_answer_outlined,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Ask questions about',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              widget.paper.title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(
      List<ChatMessage> messages, ThemeData theme, ColorScheme colorScheme) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isUser = message.role == 'user';
        return _buildMessageBubble(message, isUser, theme, colorScheme);
      },
    );
  }

  Widget _buildMessageBubble(
      ChatMessage message, bool isUser, ThemeData theme, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(
                Icons.smart_toy_outlined,
                size: 16,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isUser
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                message.content,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isUser
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildInputArea(
      AppState appState, ColorScheme colorScheme, ThemeData theme) {
    final isDisabled =
        appState.isChatLoading || appState.llmCallsThisMonth >= appState.llmCallsLimit;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: 3,
              minLines: 1,
              enabled: !isDisabled,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(appState),
              decoration: InputDecoration(
                hintText: isDisabled && appState.llmCallsThisMonth >= appState.llmCallsLimit
                    ? 'Chat limit reached'
                    : 'Ask a question...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.send, size: 20, color: colorScheme.primary),
            onPressed: isDisabled ? null : () => _sendMessage(appState),
            tooltip: 'Send',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
