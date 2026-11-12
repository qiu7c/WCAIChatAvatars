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

static Class WCAIChatSettingsClass;
static Class WCAIChatContextClass;
static Class WCAIChatContactManagerClass;
static Class WCAIChatTextModelClass;
static Class WCAIChatTextCellClass;
static Class WCAIChatControllerClass;
static Class WCAIChatSelfProfileClass;
static ptrdiff_t WCAIChatLayoutWidthOffset;
static char WCAIChatMeasureWidthKey;

static BOOL WCAIChatUsesAvatars(CommonMessageViewModel *model) {
    CBaseContact *chat = model.chatContact;
    return (chat.isWeClawBot || chat.isAIAssistant) && !model.isRecordDetail && !model.isShareConfirm;
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
    if (!url.length && WCAIChatContactManagerClass) {
        MMContext *context = [WCAIChatContextClass currentContext];
        CContactMgr *manager = [context getService:WCAIChatContactManagerClass];
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
    NSNumber *measuredWidth = objc_getAssociatedObject(model, &WCAIChatMeasureWidthKey);
    double rowWidth = measuredWidth ? measuredWidth.doubleValue : WCAIChatRowWidth(model);
    double limit = floor(rowWidth - 64 - 24 - 12);
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
        UIViewController *profile = [[WCAIChatSelfProfileClass alloc] init];
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
    return WCAIChatTextWidth((CommonMessageViewModel *)self, nativeWidth);
}
- (id)getRichTextViewConfig {
    RichTextViewConfig *config = %orig;
    CommonMessageViewModel *model = (CommonMessageViewModel *)self;
    if (model.isSender) {
        double width = config.fWidth;
        double limited = WCAIChatTextWidth(model, width);
        if (limited < width) config.fWidth = limited;
    }
    return config;
}
%end

%hook RichTextViewConfig
- (double)fWidth {
    double nativeWidth = %orig;
    id delegate = self.layoutDelegate;
    CommonMessageViewModel *model = nil;
    if ([delegate isKindOfClass:WCAIChatTextModelClass]) model = delegate;
    else if ([delegate isKindOfClass:WCAIChatTextCellClass]) model = [(CommonMessageCellView *)delegate viewModel];
    return model.isSender ? WCAIChatTextWidth(model, nativeWidth) : nativeWidth;
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
    WCAIChatSelfProfileClass = NSClassFromString(@"SettingMyProfileViewController");
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
