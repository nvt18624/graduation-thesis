package com.example.demo;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import java.util.Map;

@RestController
public class HealthController {

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "ok", "app", "java-v2-smell");
    }

    @GetMapping("/")
    public Map<String, String> index() {
        return Map.of("message", "Java v2-smell — expect PUSH BLOCKED (hardcoded credential)");
    }
}
