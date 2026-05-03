// Tweak.x
// RedditTranslator - Google Translate integration for Reddit iOS
// Hooks: UILabel long-press menu + translate button in post/comment cells

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ─────────────────────────────────────────────
// MARK: - Constants
// ─────────────────────────────────────────────

static NSString *const kSuiteName          = @"com.yourname.reddittranslator";
static NSString *const kKeyTargetLang      = @"targetLanguage";
static NSString *const kKeyAPIKey          = @"apiKey";
static NSString *const kKeyShowButton      = @"showTranslateButton";
static NSString *const kKeyEnableLongPress = @"enableLongPress";

// Associated object keys
static const char kTranslateBtnKey  = 0;
static const char kOriginalTextKey  = 0;

// ─────────────────────────────────────────────
// MARK: - Helpers
// ─────────────────────────────────────────────

static NSString *currentTargetLanguage() {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
    NSString *lang = [d stringForKey:kKeyTargetLang];
    return lang.length ? lang : @"ja";
}

static NSString *currentAPIKey() {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
    NSString *key = [d stringForKey:kKeyAPIKey];
    return key.length ? key : @"";
}

static BOOL isShowButtonEnabled() {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
    // デフォルト true
    if (![d objectForKey:kKeyShowButton]) return YES;
    return [d boolForKey:kKeyShowButton];
}

static BOOL isLongPressEnabled() {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
    if (![d objectForKey:kKeyEnableLongPress]) return YES;
    return [d boolForKey:kKeyEnableLongPress];
}

/// Google Translate REST API を叩く
static void translateText(NSString *text, void (^completion)(NSString *result, NSError *error)) {
    if (!text.length) return;

    NSString *apiKey = currentAPIKey();
    if (!apiKey.length) {
        completion(nil, [NSError errorWithDomain:@"RedditTranslator"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: @"設定から API キーを入力してください"}]);
        return;
    }

    NSString *encoded = [text stringByAddingPercentEncodingWithAllowedCharacters:
                         [NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *urlStr = [NSString stringWithFormat:
        @"https://translation.googleapis.com/language/translate/v2"
        @"?key=%@&q=%@&target=%@&format=text",
        apiKey, encoded, currentTargetLanguage()];

    NSURL *url = [NSURL URLWithString:urlStr];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";

    [[[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err || !data) { completion(nil, err); return; }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                 options:0 error:nil];
            NSString *translated = json[@"data"][@"translations"][0][@"translatedText"];
            if (translated.length) {
                // HTMLエンティティの簡易デコード
                translated = [translated stringByReplacingOccurrencesOfString:@"&amp;"  withString:@"&"];
                translated = [translated stringByReplacingOccurrencesOfString:@"&lt;"   withString:@"<"];
                translated = [translated stringByReplacingOccurrencesOfString:@"&gt;"   withString:@">"];
                translated = [translated stringByReplacingOccurrencesOfString:@"&#39;"  withString:@"'"];
                translated = [translated stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
                completion(translated, nil);
            } else {
                completion(nil, nil);
            }
        });
    }] resume];
}

/// 最前面の ViewController を取得
static UIViewController *topViewController() {
    UIWindow *window = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            window = scene.windows.firstObject;
            break;
        }
    }
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

/// ローディング Alert を表示して翻訳を実行、完了後に結果 Alert を表示
static void showTranslationFlow(NSString *text, UIViewController *presentingVC) {
    if (!text.length) return;

    // ローディング
    UIAlertController *loading = [UIAlertController
        alertControllerWithTitle:nil
        message:@"翻訳中…"
        preferredStyle:UIAlertControllerStyleAlert];
    [presentingVC presentViewController:loading animated:YES completion:nil];

    translateText(text, ^(NSString *result, NSError *error) {
        [loading dismissViewControllerAnimated:YES completion:^{
            NSString *message = result ?: (error.localizedDescription ?: @"翻訳に失敗しました");
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"翻訳結果"
                message:message
                preferredStyle:UIAlertControllerStyleAlert];

            // コピーボタン
            if (result) {
                [alert addAction:[UIAlertAction
                    actionWithTitle:@"コピー"
                    style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *a) {
                        [UIPasteboard generalPasteboard].string = result;
                    }]];
            }

            [alert addAction:[UIAlertAction
                actionWithTitle:@"閉じる"
                style:UIAlertActionStyleCancel
                handler:nil]];

            [presentingVC presentViewController:alert animated:YES completion:nil];
        }];
    });
}

// ─────────────────────────────────────────────
// MARK: - Hook 1: UILabel 長押しメニュー
// UIMenuController (iOS ~15) / UIEditMenuInteraction (iOS 16+) 両対応
// ─────────────────────────────────────────────

%hook UILabel

- (void)didMoveToWindow {
    %orig;

    // 長押し翻訳が無効なら何もしない
    if (!isLongPressEnabled()) return;

    // 10文字以上のテキストを持つラベルが対象
    if (!self.window || self.text.length < 10) return;

    // 既にジェスチャーが付いている場合はスキップ
    for (UIGestureRecognizer *gr in self.gestureRecognizers) {
        if ([gr isKindOfClass:[UILongPressGestureRecognizer class]]) return;
    }

    self.userInteractionEnabled = YES;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self
        action:@selector(rdt_labelLongPressed:)];
    lp.minimumPressDuration = 0.5;
    [self addGestureRecognizer:lp];
}

%new
- (void)rdt_labelLongPressed:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    NSString *text = self.text;
    if (!text.length) return;
    showTranslationFlow(text, topViewController());
}

%end

// ─────────────────────────────────────────────
// MARK: - Hook 2: UITableViewCell に翻訳ボタンを追加
// Reddit の投稿・コメントセルを対象にする
// ─────────────────────────────────────────────

/// セル内で最もテキスト量の多い UILabel を再帰探索
static UILabel *findMainLabel(UIView *view, NSInteger depth) {
    if (depth > 5) return nil;
    UILabel *best = nil;
    NSInteger bestLen = 20; // 20文字未満は無視

    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)sub;
            if ((NSInteger)lbl.text.length > bestLen) {
                bestLen = lbl.text.length;
                best = lbl;
            }
        }
        UILabel *found = findMainLabel(sub, depth + 1);
        if (found && (NSInteger)found.text.length > bestLen) {
            bestLen = found.text.length;
            best = found;
        }
    }
    return best;
}

%hook UITableViewCell

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    if (!isShowButtonEnabled()) return;

    // 既にボタンが付いている場合はスキップ
    if (objc_getAssociatedObject(self, &kTranslateBtnKey)) return;

    // Reddit のセルクラス名でフィルタ（不要なら削除可）
    NSString *className = NSStringFromClass([self class]);
    BOOL isRedditCell = [className containsString:@"Post"]
                     || [className containsString:@"Comment"]
                     || [className containsString:@"Reddit"]
                     || [className containsString:@"Feed"]
                     || [className containsString:@"Link"];
    if (!isRedditCell) return;

    // メインラベルを探す
    UILabel *mainLabel = findMainLabel(self.contentView, 0);
    if (!mainLabel) return;

    // 翻訳ボタンを作成
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:@"🌐 翻訳" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    btn.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.08];
    btn.layer.cornerRadius = 8;
    btn.layer.borderWidth = 0.5;
    btn.layer.borderColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.3].CGColor;
    btn.contentEdgeInsets = UIEdgeInsetsMake(3, 8, 3, 8);
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:btn];

    // mainLabel の下に配置
    [NSLayoutConstraint activateConstraints:@[
        [btn.topAnchor constraintEqualToAnchor:mainLabel.bottomAnchor constant:6],
        [btn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [btn.heightAnchor constraintEqualToConstant:22],
    ]];

    // ボタンとラベルを関連付け
    objc_setAssociatedObject(self, &kTranslateBtnKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(btn, &kOriginalTextKey, mainLabel, OBJC_ASSOCIATION_ASSIGN);

    [btn addTarget:self action:@selector(rdt_translateButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
}

%new
- (void)rdt_translateButtonTapped:(UIButton *)sender {
    UILabel *label = objc_getAssociatedObject(sender, &kOriginalTextKey);
    NSString *text = label.text;
    if (!text.length) return;
    showTranslationFlow(text, topViewController());
}

%end

// ─────────────────────────────────────────────
// MARK: - Hook 3: UICollectionViewCell（Reddit が CollectionView を使う場合）
// ─────────────────────────────────────────────

%hook UICollectionViewCell

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    if (objc_getAssociatedObject(self, &kTranslateBtnKey)) return;

    NSString *className = NSStringFromClass([self class]);
    BOOL isRedditCell = [className containsString:@"Post"]
                     || [className containsString:@"Comment"]
                     || [className containsString:@"Reddit"]
                     || [className containsString:@"Feed"];
    if (!isRedditCell) return;

    UILabel *mainLabel = findMainLabel(self.contentView, 0);
    if (!mainLabel) return;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:@"🌐 翻訳" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    btn.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.08];
    btn.layer.cornerRadius = 8;
    btn.layer.borderWidth = 0.5;
    btn.layer.borderColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.3].CGColor;
    btn.contentEdgeInsets = UIEdgeInsetsMake(3, 8, 3, 8);
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:btn];

    [NSLayoutConstraint activateConstraints:@[
        [btn.topAnchor constraintEqualToAnchor:mainLabel.bottomAnchor constant:6],
        [btn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [btn.heightAnchor constraintEqualToConstant:22],
    ]];

    objc_setAssociatedObject(self, &kTranslateBtnKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(btn, &kOriginalTextKey, mainLabel, OBJC_ASSOCIATION_ASSIGN);

    [btn addTarget:self action:@selector(rdt_translateButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
}

%new
- (void)rdt_translateButtonTapped:(UIButton *)sender {
    UILabel *label = objc_getAssociatedObject(sender, &kOriginalTextKey);
    NSString *text = label.text;
    if (!text.length) return;
    showTranslationFlow(text, topViewController());
}

%end
