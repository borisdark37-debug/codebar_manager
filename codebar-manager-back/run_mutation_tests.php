<?php

/**
 * Script de Mutation Testing pour CodeBar Manager Backend.
 * Injecte des mutations délibérées dans le code métier et vérifie que la suite de tests
 * tue systématiquement chaque mutant (taux de mortalité = 100%).
 */

$controllerPath = __DIR__ . '/app/Http/Controllers/Api/SyncController.php';
$originalCode = file_get_contents($controllerPath);

$mutants = [
    [
        'id' => 'MUTANT_1_INTERNAL_CODE_CONFLICT',
        'description' => 'Suppression de la vérification des conflits d\'internal_code',
        'target' => '$codeConflict = Product::withTrashed()',
        'replacement' => '$codeConflict = false; // Product::withTrashed()',
        'test_filter' => 'SyncEngineTest',
    ],
    [
        'id' => 'MUTANT_2_LWW_INVERSION',
        'description' => 'Inversion de la condition Last-Write-Wins (> remplacé par <)',
        'target' => '$serverLastModified > $clientTime->timestamp',
        'replacement' => '$serverLastModified < $clientTime->timestamp',
        'test_filter' => 'SyncEngineTest',
    ],
    [
        'id' => 'MUTANT_3_ROLE_ESCALATION_BYPASS',
        'description' => 'Désactivation du contrôle d\'élévation de privilèges',
        'target' => 'if (!$isSuperAdmin)',
        'replacement' => 'if (false && !$isSuperAdmin)',
        'test_filter' => 'SecurityAndPrivilegeTest',
    ],
    [
        'id' => 'MUTANT_4_IMAGE_10MB_LIMIT_BYPASS',
        'description' => 'Suppression de la limite de 10 Mo sur les images base64',
        'target' => 'elseif (strlen($imageBase64) > 10 * 1024 * 1024)',
        'replacement' => 'elseif (false && strlen($imageBase64) > 10 * 1024 * 1024)',
        'test_filter' => 'SecurityAndPrivilegeTest',
    ],
    [
        'id' => 'MUTANT_5_TOMBSTONE_PULL_OMISSION',
        'description' => 'Suppression de la collecte des tombstones de produits lors du pull',
        'target' => '$softDeletedProductUuids = Product::onlyTrashed()',
        'replacement' => '$softDeletedProductUuids = collect([]); // Product::onlyTrashed()',
        'test_filter' => 'SyncEngineTest',
    ],
    [
        'id' => 'MUTANT_6_HASH_CALCULATION_ALTERATION',
        'description' => 'Altération du hachage sécurisé du mot de passe lors de la création d\'utilisateur',
        'target' => "'password' => Hash::make(\$rawPassword),",
        'replacement' => "'password' => 'corrupted_insecure_hash_' . md5(\$rawPassword),",
        'test_filter' => 'SyncEngineTest',
    ],
];

echo "========================================================\n";
echo "   CODEBAR MANAGER - SUITE DE MUTATION TESTING (PHP)    \n";
echo "========================================================\n\n";

$totalMutants = count($mutants);
$killedMutants = 0;
$results = [];

try {
    foreach ($mutants as $idx => $m) {
        $num = $idx + 1;
        echo "[$num/$totalMutants] Test du mutant : {$m['id']}...\n";
        echo "     Description: {$m['description']}\n";

        if (strpos($originalCode, $m['target']) === false) {
            echo "     [ERREUR] Cible non trouvée dans le code source !\n";
            $results[] = ['id' => $m['id'], 'status' => 'ERROR_TARGET_NOT_FOUND'];
            continue;
        }

        // Application de la mutation
        $mutatedCode = str_replace($m['target'], $m['replacement'], $originalCode);
        file_put_contents($controllerPath, $mutatedCode);

        // Exécution du test ciblé
        $cmd = 'php artisan test --filter=' . escapeshellarg($m['test_filter']);
        exec($cmd, $output, $exitCode);

        // Si le test a échoué (exitCode != 0), le mutant est TUÉ !
        if ($exitCode !== 0) {
            echo "     -> [KILLED] Le mutant a provoqué l'échec attendu de la suite de tests.\n\n";
            $killedMutants++;
            $results[] = ['id' => $m['id'], 'status' => 'KILLED', 'desc' => $m['description']];
        } else {
            echo "     -> [SURVIVED] ALERTE : Le mutant a survécu sans faire échouer les tests !\n\n";
            $results[] = ['id' => $m['id'], 'status' => 'SURVIVED', 'desc' => $m['description']];
        }

        // Restauration immédiate
        file_put_contents($controllerPath, $originalCode);
    }
} finally {
    // Restauration de sécurité absolue
    file_put_contents($controllerPath, $originalCode);
}

$mutationScore = ($killedMutants / $totalMutants) * 100;
echo "========================================================\n";
echo "RÉSULTATS DU MUTATION TESTING :\n";
echo "Mutants générés : $totalMutants\n";
echo "Mutants tués    : $killedMutants\n";
echo "Mutants survivants : " . ($totalMutants - $killedMutants) . "\n";
printf("Score de mutation : %.2f%%\n", $mutationScore);
echo "========================================================\n";

if ($killedMutants === $totalMutants) {
    echo "SUCCÈS : 100% des mutants ont été abattus par la suite de tests !\n";
    exit(0);
} else {
    echo "ÉCHEC : Certains mutants ont survécu. Veuillez renforcer vos tests.\n";
    exit(1);
}
