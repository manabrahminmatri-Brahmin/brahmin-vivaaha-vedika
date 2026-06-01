import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Responsive design utilities for adaptive layouts
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, ScreenType screenType) builder;
  final Widget? mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResponsiveBuilder({
    super.key,
    required this.builder,
    this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    final screenType = getScreenType(context);
    
    if (screenType == ScreenType.mobile && mobile != null) {
      return mobile!;
    } else if (screenType == ScreenType.tablet && tablet != null) {
      return tablet!;
    } else if (screenType == ScreenType.desktop && desktop != null) {
      return desktop!;
    }
    
    return builder(context, screenType);
  }

  static ScreenType getScreenType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    
    if (width < ResponsiveConstants.mobileBreakpoint) {
      return ScreenType.mobile;
    } else if (width < ResponsiveConstants.tabletBreakpoint) {
      return ScreenType.tablet;
    } else {
      return ScreenType.desktop;
    }
  }

  static bool isMobile(BuildContext context) {
    return getScreenType(context) == ScreenType.mobile;
  }

  static bool isTablet(BuildContext context) {
    return getScreenType(context) == ScreenType.tablet;
  }

  static bool isDesktop(BuildContext context) {
    return getScreenType(context) == ScreenType.desktop;
  }

  static double getWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  static double getHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }

  static double getAdaptiveWidth(BuildContext context) {
    final width = getWidth(context);
    final screenType = getScreenType(context);
    
    switch (screenType) {
      case ScreenType.mobile:
        return width;
      case ScreenType.tablet:
        return width * 0.8;
      case ScreenType.desktop:
        return width * 0.6;
    }
  }

  static EdgeInsets getAdaptivePadding(BuildContext context) {
    final screenType = getScreenType(context);
    
    switch (screenType) {
      case ScreenType.mobile:
        return const EdgeInsets.all(16);
      case ScreenType.tablet:
        return const EdgeInsets.all(24);
      case ScreenType.desktop:
        return const EdgeInsets.all(32);
    }
  }

  static double getAdaptiveFontSize(BuildContext context, double mobileSize) {
    final screenType = getScreenType(context);
    
    switch (screenType) {
      case ScreenType.mobile:
        return mobileSize;
      case ScreenType.tablet:
        return mobileSize * 1.1;
      case ScreenType.desktop:
        return mobileSize * 1.2;
    }
  }

  static int getAdaptiveColumns(BuildContext context) {
    final screenType = getScreenType(context);
    
    switch (screenType) {
      case ScreenType.mobile:
        return 1;
      case ScreenType.tablet:
        return 2;
      case ScreenType.desktop:
        return 3;
    }
  }

  static double getAdaptiveSpacing(BuildContext context) {
    final screenType = getScreenType(context);
    
    switch (screenType) {
      case ScreenType.mobile:
        return 16;
      case ScreenType.tablet:
        return 24;
      case ScreenType.desktop:
        return 32;
    }
  }
}

/// Responsive constants
class ResponsiveConstants {
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1024;
  static const double desktopBreakpoint = 1440;
  
  static const double maxContentWidth = 1200;
  static const double sideBarWidth = 280;
  static const double appBarHeight = 64;
}

/// Screen type enum
enum ScreenType {
  mobile,
  tablet,
  desktop,
}

/// Responsive layout widget
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (context, screenType) {
        switch (screenType) {
          case ScreenType.mobile:
            return mobile;
          case ScreenType.tablet:
            return tablet ?? mobile;
          case ScreenType.desktop:
            return desktop ?? tablet ?? mobile;
        }
      },
    );
  }
}

/// Responsive grid view
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double? childAspectRatio;
  final double? crossAxisSpacing;
  final double? mainAxisSpacing;
  final EdgeInsets? padding;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.childAspectRatio,
    this.crossAxisSpacing,
    this.mainAxisSpacing,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final columns = ResponsiveBuilder.getAdaptiveColumns(context);
    final spacing = ResponsiveBuilder.getAdaptiveSpacing(context);
    
    return GridView.builder(
      padding: padding ?? ResponsiveBuilder.getAdaptivePadding(context),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: childAspectRatio ?? 1.2,
        crossAxisSpacing: crossAxisSpacing ?? spacing,
        mainAxisSpacing: mainAxisSpacing ?? spacing,
      ),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );
  }
}

/// Responsive container with max width
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsets? padding;
  final Alignment? alignment;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = ResponsiveBuilder.getWidth(context);
    final containerWidth = maxWidth ?? ResponsiveConstants.maxContentWidth;
    final useMaxWidth = screenWidth > containerWidth;
    
    return Container(
      width: useMaxWidth ? containerWidth : null,
      alignment: alignment,
      padding: padding,
      child: child,
    );
  }
}

/// Responsive navigation rail
class ResponsiveNavigation extends StatelessWidget {
  final List<NavigationItem> items;
  final int selectedIndex;
  final Function(int) onItemSelected;
  final Widget? body;

  const ResponsiveNavigation({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onItemSelected,
    this.body,
  });

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      mobile: _buildMobileLayout(),
      tablet: _buildTabletLayout(),
      desktop: _buildDesktopLayout(),
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      body: body,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: onItemSelected,
        items: items.map((item) => BottomNavigationBarItem(
          icon: Icon(item.icon),
          label: item.label,
        )).toList(),
      ),
    );
  }

  Widget _buildTabletLayout() {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: onItemSelected,
            extended: true,
            destinations: items.map((item) => NavigationRailDestination(
              icon: Icon(item.icon),
              label: Text(item.label),
            )).toList(),
          ),
          Expanded(child: body ?? Container()),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: ResponsiveConstants.sideBarWidth,
            child: ListView(
              children: items.map((item) => ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                selected: selectedIndex == items.indexOf(item),
                onTap: () => onItemSelected(items.indexOf(item)),
              )).toList(),
            ),
          ),
          Expanded(child: body ?? Container()),
        ],
      ),
    );
  }
}

/// Navigation item model
class NavigationItem {
  final IconData icon;
  final String label;
  final Widget? page;

  const NavigationItem({
    required this.icon,
    required this.label,
    this.page,
  });
}

/// Responsive card widget
class ResponsiveCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? margin;
  final EdgeInsets? padding;
  final double? borderRadius;
  final Color? color;
  final VoidCallback? onTap;

  const ResponsiveCard({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.borderRadius,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveBuilder.getScreenType(context);
    final adaptiveMargin = margin ?? ResponsiveBuilder.getAdaptivePadding(context);
    final adaptivePadding = padding ?? ResponsiveBuilder.getAdaptivePadding(context);
    final adaptiveRadius = borderRadius ?? (screenType == ScreenType.mobile ? 12.0 : 16.0);
    
    return Container(
      margin: adaptiveMargin,
      padding: adaptivePadding,
      decoration: BoxDecoration(
        color: color ?? AC.card(context),
        borderRadius: BorderRadius.circular(adaptiveRadius),
        boxShadow: [
          BoxShadow(
            color: AC.surface(context),
            blurRadius: screenType == ScreenType.mobile ? 4 : 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(adaptiveRadius),
              child: child,
            )
          : child,
    );
  }
}

/// Responsive text widget
class ResponsiveText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const ResponsiveText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final baseFontSize = style?.fontSize ?? 16;
    final adaptiveFontSize = ResponsiveBuilder.getAdaptiveFontSize(context, baseFontSize);
    
    return Text(
      text,
      style: style?.copyWith(fontSize: adaptiveFontSize),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// Responsive button widget
class ResponsiveButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final ButtonStyle? style;
  final Widget? icon;
  final bool fullWidth;

  const ResponsiveButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.style,
    this.icon,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveBuilder.getScreenType(context);
    final buttonWidth = fullWidth ? double.infinity : null;
    final buttonHeight = screenType == ScreenType.mobile ? 48.0 : 56.0;
    
    return SizedBox(
      width: buttonWidth,
      height: buttonHeight,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: style,
        icon: icon,
        label: ResponsiveText(
          text,
          style: TextStyle(
            fontSize: screenType == ScreenType.mobile ? 16 : 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Responsive image widget
class ResponsiveImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const ResponsiveImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveBuilder.getScreenType(context);
    final adaptiveWidth = width ?? ResponsiveBuilder.getAdaptiveWidth(context);
    final adaptiveHeight = height ?? (screenType == ScreenType.mobile ? 200 : 300);
    
    return Image.network(
      imageUrl,
      width: adaptiveWidth,
      height: adaptiveHeight,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return SizedBox(
          width: adaptiveWidth,
          height: adaptiveHeight,
          child: placeholder ?? const Center(child: CircularProgressIndicator()),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return SizedBox(
          width: adaptiveWidth,
          height: adaptiveHeight,
          child: errorWidget ?? const Icon(Icons.error),
        );
      },
    );
  }
}

/// Responsive scaffold with adaptive layout
class ResponsiveScaffold extends StatelessWidget {
  final Widget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final Widget? endDrawer;
  final EdgeInsets? padding;

  const ResponsiveScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.drawer,
    this.endDrawer,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveBuilder.getScreenType(context);
    
    return Scaffold(
      appBar: appBar != null ? PreferredSize(
        preferredSize: Size.fromHeight(screenType == ScreenType.mobile ? 60 : 80),
        child: appBar!,
      ) : null,
      drawer: drawer,
      endDrawer: endDrawer,
      body: ResponsiveContainer(
        padding: padding ?? ResponsiveBuilder.getAdaptivePadding(context),
        child: body,
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}
