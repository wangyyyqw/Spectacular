import 'package:flutter/material.dart';

import '../storage/book_review_store.dart';

/// 读完表单与书评编辑器共用的正文输入，统一长度限制与换行行为。
class BookReviewField extends StatelessWidget {
  const BookReviewField({
    super.key,
    required this.label,
    required this.controller,
    required this.fieldKey,
    this.readOnly = false,
    this.maxLines = 8,
  });

  final String label;
  final TextEditingController controller;
  final Key fieldKey;
  final bool readOnly;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      TextField(
        key: fieldKey,
        controller: controller,
        readOnly: readOnly,
        minLines: 4,
        maxLines: maxLines,
        maxLength: BookReview.maxContentLength,
        textInputAction: TextInputAction.newline,
        decoration: const InputDecoration(
          hintText: '写下这本书带给你的感受…',
          alignLabelWithHint: true,
        ),
      ),
    ],
  );
}
