import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: 'https://qhlpiosfbvrjobsqlmvg.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFobHBpb3NmYnZyam9ic3FsbXZnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQzMDgzNTgsImV4cCI6MjA2OTg4NDM1OH0.jd9m_sXHg-zTfLaGgoLp7Q9-EIf1SvEv6MK-1WvOpI8',
  );
}
