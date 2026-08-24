import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// In-app playback via the YouTube IFrame player embed — no API key needed
/// for playback itself (only listing/searching a channel's uploads needs
/// the Data API, which is what's still gated on docs/OPEN_QUESTIONS.md).
/// A livestream is just the same embed for a video that happens to be
/// live; YouTube's player handles that automatically.
class MediaPlayerScreen extends StatefulWidget {
  const MediaPlayerScreen({required this.post, super.key});

  final MediaPostModel post;

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..loadRequest(
        Uri.parse('https://www.youtube-nocookie.com/embed/${widget.post.externalId}?autoplay=1&playsinline=1&rel=0'),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.post.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            AspectRatio(aspectRatio: 16 / 9, child: WebViewWidget(controller: _controller)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(FlcSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(widget.post.title, style: FlcTextStyles.h3),
                    if (widget.post.description != null) ...<Widget>[
                      const SizedBox(height: FlcSpace.sm),
                      Text(widget.post.description!, style: FlcTextStyles.body),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
