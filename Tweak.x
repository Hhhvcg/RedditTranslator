#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *const kSuite  = @"com.yourname.reddittranslator";
static const char kBtnKey      = 0;
static const char kLblKey      = 0;

// ── 設定読み込み ──────────────────────────────
static NSString *targetLang() {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kSuite];
    NSString *l = [d stringForKey:@"targetLanguage"];
    return l.length ? l : @"ja";
}
static NSString *apiKey() {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kSuite];
    return [d stringForKey:@"apiKey"] ?: @"";
}

// ── トップVCを取得 ────────────────────────────
static UIViewController *topVC() {
    UIWindow *win = nil;
    for (UIWindowScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class]) { win = s.windows.firstObject; break; }
    UIViewController *vc = win.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

// ── 翻訳実行 ─────────────────────────────────
static void translate(NSString *text, void(^done)(NSString*)) {
    NSString *key = apiKey();
    if (!key.length) { done(@"設定でAPIキーを入力してください"); return; }
    NSString *enc = [text stringByAddingPercentEncodingWithAllowedCharacters:
                     NSCharacterSet.URLQueryAllowedCharacterSet];
    NSString *us = [NSString stringWithFormat:
        @"https://translation.googleapis.com/language/translate/v2?key=%@&q=%@&target=%@&format=text",
        key, enc, targetLang()];
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:us]
        completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!d) { done(@"通信エラー"); return; }
            NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            NSString *t = j[@"data"][@"translations"][0][@"translatedText"] ?: @"失敗";
            t = [t stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];
            t = [t stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
            done(t);
        });
    }] resume];
}

// ── 翻訳フロー表示 ────────────────────────────
static void showFlow(NSString *text) {
    if (!text.length) return;
    UIViewController *vc = topVC();
    UIAlertController *loading = [UIAlertController alertControllerWithTitle:nil
        message:@"翻訳中…" preferredStyle:UIAlertControllerStyleAlert];
    [vc presentViewController:loading animated:YES completion:nil];
    translate(text, ^(NSString *result) {
        [loading dismissViewControllerAnimated:YES completion:^{
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"翻訳結果"
                message:result preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"コピー"
                style:UIAlertActionStyleDefault handler:^(id _){
                UIPasteboard.generalPasteboard.string = result; }]];
            [a addAction:[UIAlertAction actionWithTitle:@"閉じる"
                style:UIAlertActionStyleCancel handler:nil]];
            [topVC() presentViewController:a animated:YES completion:nil];
        }];
    });
}

// ── UILabel スワイズル ────────────────────────
static void (*orig_labelDidMoveToWindow)(UILabel*, SEL);
static void hook_labelDidMoveToWindow(UILabel *self, SEL _cmd) {
    orig_labelDidMoveToWindow(self, _cmd);
    if (!self.window || self.text.length < 10) return;
    for (UIGestureRecognizer *g in self.gestureRecognizers)
        if ([g isKindOfClass:UILongPressGestureRecognizer.class]) return;
    self.userInteractionEnabled = YES;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(rdt_longPress:)];
    lp.minimumPressDuration = 0.5;
    [self addGestureRecognizer:lp];
}

// ── UITableViewCell スワイズル ─────────────────
static UILabel *findLabel(UIView *v, int depth) {
    if (depth > 5) return nil;
    UILabel *best = nil; NSInteger bestLen = 20;
    for (UIView *s in v.subviews) {
        if ([s isKindOfClass:UILabel.class]) {
            UILabel *l = (UILabel*)s;
            if ((NSInteger)l.text.length > bestLen) { bestLen = l.text.length; best = l; }
        }
        UILabel *f = findLabel(s, depth+1);
        if (f && (NSInteger)f.text.length > bestLen) { bestLen = f.text.length; best = f; }
    }
    return best;
}

static void addTranslateButton(UIView *contentView, id cell) {
    if (objc_getAssociatedObject(cell, &kBtnKey)) return;
    NSString *cn = NSStringFromClass([cell class]);
    if (![cn containsString:@"Post"] && ![cn containsString:@"Comment"]
     && ![cn containsString:@"Reddit"] && ![cn containsString:@"Feed"]
     && ![cn containsString:@"Link"]) return;
    UILabel *lbl = findLabel(contentView, 0);
    if (!lbl) return;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:@"🌐 翻訳" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    btn.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.08];
    btn.layer.cornerRadius = 8;
    btn.layer.borderWidth = 0.5;
    btn.layer.borderColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.3].CGColor;
    btn.contentEdgeInsets = UIEdgeInsetsMake(3,8,3,8);
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:btn];
    [NSLayoutConstraint activateConstraints:@[
        [btn.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:6],
        [btn.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-12],
        [btn.heightAnchor constraintEqualToConstant:22],
    ]];
    objc_setAssociatedObject(cell, &kBtnKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(btn,  &kLblKey, lbl, OBJC_ASSOCIATION_ASSIGN);
    [btn addTarget:cell action:@selector(rdt_translateTapped:) forControlEvents:UIControlEventTouchUpInside];
}

static void (*orig_cellDidMove)(UITableViewCell*, SEL);
static void hook_cellDidMove(UITableViewCell *self, SEL _cmd) {
    orig_cellDidMove(self, _cmd);
    if (!self.window) return;
    addTranslateButton(self.contentView, self);
}

static void (*orig_cvCellDidMove)(UICollectionViewCell*, SEL);
static void hook_cvCellDidMove(UICollectionViewCell *self, SEL _cmd) {
    orig_cvCellDidMove(self, _cmd);
    if (!self.window) return;
    addTranslateButton(self.contentView, self);
}

// ── カテゴリ（新規メソッド追加）─────────────────
@interface UILabel (RDT) @end
@implementation UILabel (RDT)
- (void)rdt_longPress:(UILongPressGestureRecognizer*)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    showFlow(self.text);
}
@end

@interface UITableViewCell (RDT) @end
@implementation UITableViewCell (RDT)
- (void)rdt_translateTapped:(UIButton*)btn {
    UILabel *l = objc_getAssociatedObject(btn, &kLblKey);
    showFlow(l.text);
}
@end

@interface UICollectionViewCell (RDT) @end
@implementation UICollectionViewCell (RDT)
- (void)rdt_translateTapped:(UIButton*)btn {
    UILabel *l = objc_getAssociatedObject(btn, &kLblKey);
    showFlow(l.text);
}
@end

// ── dylib ロード時に自動実行 ──────────────────
__attribute__((constructor)) static void RDTInit() {
    // UILabel
    Method m1 = class_getInstanceMethod(UILabel.class, @selector(didMoveToWindow));
    orig_labelDidMoveToWindow = (void*)method_getImplementation(m1);
    method_setImplementation(m1, (IMP)hook_labelDidMoveToWindow);

    // UITableViewCell
    Method m2 = class_getInstanceMethod(UITableViewCell.class, @selector(didMoveToWindow));
    orig_cellDidMove = (void*)method_getImplementation(m2);
    method_setImplementation(m2, (IMP)hook_cellDidMove);

    // UICollectionViewCell
    Method m3 = class_getInstanceMethod(UICollectionViewCell.class, @selector(didMoveToWindow));
    orig_cvCellDidMove = (void*)method_getImplementation(m3);
    method_setImplementation(m3, (IMP)hook_cvCellDidMove);
}
