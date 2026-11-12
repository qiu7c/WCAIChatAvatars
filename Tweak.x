#import <UIKit/UIKit.h>
#import <math.h>
#import <objc/runtime.h>
#import <string.h>

@interface CBaseContact : NSObject
@property (nonatomic, readonly) NSString *m_nsUsrName;
@property (nonatomic, readonly) NSString *m_nsHeadImgUrl;
- (BOOL)isWeClawBot;
- (BOOL)isAIAssistant;
@end

@interface SettingUtil : NSObject
+ (NSString *)getCurUsrName;
@end

@interface CContactMgr : NSObject
- (CBaseContact *)getSelfContact;
- (CBaseContact *)getContactByName:(NSString *)name;
@end

@interface MMContext : NSObject
+ (instancetype)currentContext;
- (CContactMgr *)getService:(Class)service;
@end

@interface CommonMessageViewModel : NSObject
@property (nonatomic, readonly) CBaseContact *chatContact;
@property (nonatomic, readonly) CBaseContact *contact;
@property (nonatomic, readonly) BOOL isSender;
@property (nonatomic, readonly) NSString *customHeadImageUrl;
- (BOOL)isShowHeadImage;
- (BOOL)isRecordDetail;
- (BOOL)isShareConfirm;
@end

@interface MMHeadImageView : UIView
@property (nonatomic, readonly) NSString *nsUsrName;
@property (nonatomic, readonly) UIImageView *headImageView;
- (void)updateUsrName:(NSString *)name withHeadImgUrl:(NSString *)url;
- (void)checkAndUpdateImage;
@end

@interface CommonMessageCellView : UIView
@property (nonatomic, readonly) CommonMessageViewModel *viewModel;
- (MMHeadImageView *)getHeadImageView;
@end

@interface StreamMDMessageCellView : CommonMessageCellView
- (BOOL)shouldExpandAIBubbleToMaxWidth;
@end

@interface RichTextViewConfig : NSObject
@property (nonatomic) double fWidth;
@property (nonatomic, weak) id layoutDelegate;
@end

@interface BaseMsgContentViewController : UIViewController
- (void)openChatInfo:(id)sender;
@end

@interface ContactInfoViewController : UIViewController
- (instancetype)initWithTitle:(NSString *)title;
- (void)setM_contact:(CBaseContact *)contact;
@end

static Class WCAIChatSettingsClass;
static Class WCAIChatContextClass;
static Class WCAIChatContactManagerClass;
static Class WCAIChatTextModelClass;
static Class WCAIChatTextCellClass;
static Class WCAIChatControllerClass;
static Class WCAIChatSelfProfileClass;
static ptrdiff_t WCAIChatLayoutWidthOffset;
static char WCAIChatMeasureWidthKey;
static __thread double WCAIChatMeasuringOutgoingLimit;

static BOOL WCAIChatUsesAvatars(CommonMessageViewModel *model) {
    CBaseContact *chat = model.chatContact;
    return (chat.isWeClawBot || chat.isAIAssistant) && !model.isRecordDetail && !model.isShareConfirm;
}

static CContactMgr *WCAIChatContactManager(void) {
    if (!WCAIChatContactManagerClass) return nil;
    MMContext *context = [WCAIChatContextClass currentContext];
    return [context getService:WCAIChatContactManagerClass];
}

static void WCAIChatBindAvatar(CommonMessageCellView *cell) {
    CommonMessageViewModel *model = cell.viewModel;
    if (!WCAIChatUsesAvatars(model)) return;
    MMHeadImageView *avatar = [cell getHeadImageView];
    if (!avatar) return;

    BOOL sender = model.isSender;
    CBaseContact *contact = sender ? model.contact : model.chatContact;
    NSString *name = sender ? [WCAIChatSettingsClass getCurUsrName] : contact.m_nsUsrName;
    if (!name.length || ([avatar.nsUsrName isEqualToString:name] && avatar.headImageView.image)) return;

    NSString *url = sender ? nil : model.customHeadImageUrl;
    if (!url.length && [contact.m_nsUsrName isEqualToString:name]) url = contact.m_nsHeadImgUrl;
    if (!url.length) {
        CContactMgr *manager = WCAIChatContactManager();
        CBaseContact *storedContact = sender ? [manager getSelfContact] : [manager getContactByName:name];
        if ([storedContact.m_nsUsrName isEqualToString:name]) url = storedContact.m_nsHeadImgUrl;
    }
    [avatar updateUsrName:name withHeadImgUrl:url ?: @""];
    if (!avatar.headImageView.image) [avatar checkAndUpdateImage];
}

static double WCAIChatRowWidth(CommonMessageViewModel *model) {
    double width = 0;
    const char *bytes = (const char *)(__bridge const void *)model;
    memcpy(&width, bytes + WCAIChatLayoutWidthOffset, sizeof(width));
    return width;
}

static double WCAIChatTextWidth(CommonMessageViewModel *model, double nativeWidth) {
    if (nativeWidth <= 0 || !WCAIChatUsesAvatars(model)) return nativeWidth;
    // Reserve the 64 pt avatar column, 24 pt bubble padding, and 12 pt opposite margin.
    double rowWidth = WCAIChatRowWidth(model);
    double limit = floor(rowWidth - 64 - 24 - 12);
    return limit > 0 ? MIN(nativeWidth, limit) : nativeWidth;
}

static double WCAIChatOutgoingLimit(CommonMessageViewModel *model) {
    if (!model.isSender || !WCAIChatUsesAvatars(model)) return 0;
    NSNumber *measured = objc_getAssociatedObject(model, &WCAIChatMeasureWidthKey);
    double rowWidth = measured ? measured.doubleValue : WCAIChatRowWidth(model);
    // Match the assistant bubble's roughly 46 pt opposite-side margin in the dump.
    return MAX(0, floor(rowWidth - 64 - 24 - 47));
}

static double WCAIChatOutgoingWidth(id delegate, double nativeWidth) {
    if (nativeWidth <= 0) return nativeWidth;
    double limit = WCAIChatMeasuringOutgoingLimit;
    if (limit <= 0) {
        CommonMessageViewModel *model = nil;
        if ([delegate isKindOfClass:WCAIChatTextModelClass]) model = delegate;
        else if ([delegate isKindOfClass:WCAIChatTextCellClass]) model = [(CommonMessageCellView *)delegate viewModel];
        limit = WCAIChatOutgoingLimit(model);
    }
    return limit > 0 ? MIN(nativeWidth, limit) : nativeWidth;
}

%hook CommonMessageViewModel
- (BOOL)isShowHeadImage {
    BOOL native = %orig;
    return native || WCAIChatUsesAvatars(self);
}
%end

%hook CommonMessageCellView
- (void)initHeadImageView {
    %orig;
    WCAIChatBindAvatar(self);
}
- (void)setViewModel:(id)model {
    %orig(model);
    WCAIChatBindAvatar(self);
}
- (void)onHeadImageClicked:(id)sender {
    CommonMessageViewModel *model = self.viewModel;
    if (!WCAIChatUsesAvatars(model)) {
        %orig(sender);
        return;
    }

    UIResponder *responder = self.nextResponder;
    while (responder && ![responder isKindOfClass:WCAIChatControllerClass]) responder = responder.nextResponder;
    BaseMsgContentViewController *chat = (BaseMsgContentViewController *)responder;
    UINavigationController *navigation = chat.navigationController;
    if (!chat || navigation.topViewController != chat) return;

    if (model.isSender) {
        CBaseContact *contact = [WCAIChatContactManager() getSelfContact];
        if (!contact.m_nsUsrName.length) return;
        ContactInfoViewController *profile = [[WCAIChatSelfProfileClass alloc] initWithTitle:@"个人资料"];
        [profile setM_contact:contact];
        if (profile) [navigation pushViewController:profile animated:YES];
    } else {
        [chat openChatInfo:chat.navigationItem.rightBarButtonItem];
    }
}
%end

%hook TextMessageViewModel
- (CGSize)measure:(CGSize)size {
    CommonMessageViewModel *model = (CommonMessageViewModel *)self;
    if (model.isSender && WCAIChatUsesAvatars(model) && isfinite(size.width) && size.width > 0) {
        objc_setAssociatedObject(model, &WCAIChatMeasureWidthKey, @(size.width), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGSize measured = %orig(size);
    return measured;
}
- (double)labelWidth {
    double nativeWidth = %orig;
    return WCAIChatOutgoingWidth(self, nativeWidth);
}
- (id)getRichTextViewConfig {
    RichTextViewConfig *config = %orig;
    double width = config.fWidth;
    double limited = WCAIChatOutgoingWidth(self, width);
    if (limited < width) config.fWidth = limited;
    return config;
}
- (CGSize)calculateContentTextSize {
    double previous = WCAIChatMeasuringOutgoingLimit;
    WCAIChatMeasuringOutgoingLimit = WCAIChatOutgoingLimit((CommonMessageViewModel *)self);
    CGSize measured = %orig;
    WCAIChatMeasuringOutgoingLimit = previous;
    return measured;
}
- (CGSize)sizeForContent:(id)content layoutDelegate:(id)delegate autoLineSpacing:(BOOL)autoSpacing outArrStyles:(id __autoreleasing *)styles {
    double previous = WCAIChatMeasuringOutgoingLimit;
    double limit = WCAIChatOutgoingLimit((CommonMessageViewModel *)self);
    if (limit > 0) WCAIChatMeasuringOutgoingLimit = limit;
    CGSize measured = %orig(content, delegate, autoSpacing, styles);
    WCAIChatMeasuringOutgoingLimit = previous;
    return measured;
}
%end

%hook RichTextViewConfig
- (double)fWidth {
    double nativeWidth = %orig;
    return WCAIChatOutgoingWidth(self.layoutDelegate, nativeWidth);
}
%end

%hook RichTextView
+ (CGSize)sizeForContent:(id)content font:(id)font width:(double)width parserType:(unsigned long long)parser delegate:(id)delegate outArrStyles:(id __autoreleasing *)styles {
    double limited = WCAIChatOutgoingWidth(delegate, width);
    CGSize measured = %orig(content, font, limited, parser, delegate, styles);
    return measured;
}
+ (CGSize)sizeForContent:(id)content font:(id)font width:(double)width lineSpacing:(double)spacing lineNumber:(unsigned long long)lines parserType:(unsigned long long)parser delegate:(id)delegate outArrStyles:(id __autoreleasing *)styles rightIconPadding:(double)padding originX:(double)x textAttribute:(id)attributes expandAndCollapseObj:(id)expand imageLayout:(id)images {
    double limited = WCAIChatOutgoingWidth(delegate, width);
    CGSize measured = %orig(content, font, limited, spacing, lines, parser, delegate, styles, padding, x, attributes, expand, images);
    return measured;
}
+ (CGSize)sizeForPrefixContent:(id)prefix TargetContent:(id)content TargetParserString:(id)parsed SuffixContent:(id)suffix font:(id)font width:(double)width lineSpacing:(double)spacing lineNumber:(unsigned long long)lines linkTextVisiableLength:(unsigned int)linkLength parserType:(unsigned long long)parser delegate:(id)delegate outArrStyles:(id __autoreleasing *)styles {
    double limited = WCAIChatOutgoingWidth(delegate, width);
    CGSize measured = %orig(prefix, content, parsed, suffix, font, limited, spacing, lines, linkLength, parser, delegate, styles);
    return measured;
}
%end

%hook StreamMDMessageViewModel
- (double)labelWidth {
    double nativeWidth = %orig;
    return WCAIChatTextWidth((CommonMessageViewModel *)self, nativeWidth);
}
- (double)resultTextMaxWidth {
    double nativeWidth = %orig;
    return WCAIChatTextWidth((CommonMessageViewModel *)self, nativeWidth);
}
- (double)thinkingTextMaxWidth {
    double nativeWidth = %orig;
    return WCAIChatTextWidth((CommonMessageViewModel *)self, nativeWidth);
}
- (id)markdownHeightCacheKey {
    id key = %orig;
    CommonMessageViewModel *model = (CommonMessageViewModel *)self;
    if (WCAIChatUsesAvatars(model) && [key isKindOfClass:NSString.class]) {
        return [key stringByAppendingFormat:@"|wcaichatavatars-%.2f", WCAIChatRowWidth(model)];
    }
    return key;
}
%end

%hook StreamMDMessageCellView
- (BOOL)shouldExpandAIBubbleToMaxWidth {
    BOOL expands = %orig;
    return expands && !WCAIChatUsesAvatars(self.viewModel);
}
%end

%ctor {
    Class contact = NSClassFromString(@"CBaseContact");
    Class model = NSClassFromString(@"CommonMessageViewModel");
    Class streamCell = NSClassFromString(@"StreamMDMessageCellView");
    WCAIChatSettingsClass = NSClassFromString(@"SettingUtil");
    WCAIChatTextModelClass = NSClassFromString(@"TextMessageViewModel");
    WCAIChatTextCellClass = NSClassFromString(@"TextMessageCellView");
    Class chatController = NSClassFromString(@"BaseMsgContentViewController");
    if ([chatController instancesRespondToSelector:@selector(openChatInfo:)]) WCAIChatControllerClass = chatController;
    Class profile = NSClassFromString(@"ContactInfoViewController");
    if ([profile instancesRespondToSelector:@selector(initWithTitle:)] &&
        [profile instancesRespondToSelector:@selector(setM_contact:)]) WCAIChatSelfProfileClass = profile;
    Class context = NSClassFromString(@"MMContext");
    Class contactManager = NSClassFromString(@"CContactMgr");
    if ([context respondsToSelector:@selector(currentContext)] &&
        [context instancesRespondToSelector:@selector(getService:)] &&
        [contactManager instancesRespondToSelector:@selector(getSelfContact)] &&
        [contactManager instancesRespondToSelector:@selector(getContactByName:)]) {
        WCAIChatContextClass = context;
        WCAIChatContactManagerClass = contactManager;
    }
    Ivar width = class_getInstanceVariable(model, "m_layoutWidth");
    if (!width || strcmp(ivar_getTypeEncoding(width), @encode(double)) != 0) return;
    WCAIChatLayoutWidthOffset = ivar_getOffset(width);
    if ([contact instancesRespondToSelector:@selector(isWeClawBot)] &&
        [contact instancesRespondToSelector:@selector(isAIAssistant)] &&
        [model instancesRespondToSelector:@selector(chatContact)] &&
        [model instancesRespondToSelector:@selector(isRecordDetail)] &&
        [model instancesRespondToSelector:@selector(isShareConfirm)] &&
        [model instancesRespondToSelector:@selector(isShowHeadImage)] &&
        [streamCell instancesRespondToSelector:@selector(viewModel)] &&
        [streamCell instancesRespondToSelector:@selector(shouldExpandAIBubbleToMaxWidth)] &&
        [WCAIChatSettingsClass respondsToSelector:@selector(getCurUsrName)]) {
        %init;
    }
}
