import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cliente/providers/auth_provider.dart';
import 'package:cliente/screens/register_screen.dart';
import 'package:cliente/screens/contacts_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    // Inicializa a conexão com o servidor sem rebuild desnecessário
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.initialize();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _updateState(AuthProvider authProvider) {
    if (_isLoading != authProvider.isLoading ||
        _errorMessage != authProvider.errorMessage) {
      setState(() {
        _isLoading = authProvider.isLoading;
        _errorMessage = authProvider.errorMessage;
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _login(BuildContext context) async {
    if (_formKey.currentState!.validate()) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      final success = await authProvider.login(
        _usernameController.text.trim(),
        _passwordController.text.trim(),
      );

      if (success) {
        // Navega para a tela de contatos
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ContactsScreen()),
        );
      } else {
        _showErrorSnackBar(authProvider.errorMessage);
      }
    }
  }

  void _navigateToRegister(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    _updateState(authProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Login - Sistema de Chat')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              const Icon(Icons.chat, size: 80, color: Colors.blue),
              const SizedBox(height: 20),

              const Text(
                'Sistema de Chat',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),

              // Campo Username
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Usuário',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, digite seu usuário';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Campo Password
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, digite sua senha';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 30),

              // Botão Login
              if (_isLoading)
                const CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: () => _login(context),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('Entrar'),
                ),

              const SizedBox(height: 20),

              // Botão Registrar
              OutlinedButton(
                onPressed: () => _navigateToRegister(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('Criar Nova Conta'),
              ),

              // Mensagem de erro
              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
