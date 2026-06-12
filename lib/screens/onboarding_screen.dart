import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/auth/auth_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int currentIndex = 0;

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingSeen', true);

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const AuthScreen(initialMode: AuthScreenMode.entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _controller,
            onPageChanged: (index) {
              setState(() => currentIndex = index);
            },
            children: [buildFirstPage(), buildSecondPage()],
          ),

          // Skip Button
          Positioned(
            top: 50,
            right: 20,
            child: TextButton(
              onPressed: completeOnboarding,
              child: const Text("Skip", style: TextStyle(color: Colors.white)),
            ),
          ),

          // Bottom Dots + Button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                buildDotsIndicator(),
                const SizedBox(height: 20),
                if (currentIndex == 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: ElevatedButton(
                      onPressed: completeOnboarding,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      ),
                      child: const Text(
                        "Get Started",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ FIRST PAGE
  Widget buildFirstPage() {
    return Stack(
      children: [
        // Background Image
        Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/images/1bg.jpeg"),
              fit: BoxFit.cover,
            ),
          ),
        ),

        // Dark Gradient Overlay
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.transparent,
                Colors.transparent,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),

        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 190),

              // 🔥 HADITH ABOVE THE BODIES (NOW PERFECTLY CENTERED)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: const SizedBox(
                  width: double.infinity,
                  child: Text(
                    "“The first deed for which a person\n"
                    "will be held accountable on the Day\n"
                    "of Judgment is the prayer (Namaz).\n"
                    "— Prophet Muhammad ﷺ\n"
                    "(Abu Dawood 864, Tirmidhi 413)”",
                    textAlign: TextAlign.center, // ✅ changed from justify
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      height: 2.6,
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // 🔥 APP NAME CENTER BOTTOM (ABOVE DOTS)
              const Padding(
                padding: EdgeInsets.only(bottom: 90),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    "Tawheed Namaz Reminder",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: Color.fromARGB(255, 255, 251, 8),
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ✅ SECOND PAGE (UNCHANGED - already centered)
  Widget buildSecondPage() {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/images/1bg.jpeg"),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.transparent,
                Colors.transparent,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),

        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 250),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    "Never Miss a Salah\n\nSmart Azan & Jamat Reminders",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildDotsIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        2,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: currentIndex == index ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: currentIndex == index
                ? Colors.white
                : const Color(0x80FFFFFF),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}
